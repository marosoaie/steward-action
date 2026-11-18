// Replaces a pull request's summary comment when the Dangerfile didn't
// build, or ended without having reported, so that an earlier push's
// summary doesn't read as current beside a red check. action.yml runs it
// with actions/github-script, which has no curl or jq to need: a swift
// container has neither. Returns what it did, the step's `result`.
//
// It finds the comment as Steward does: the oldest one by SUMMARY_AUTHOR
// (github-actions[bot] when that's empty) whose first line is the marker,
// through every page, and keeps the marker so the next run updates the same
// comment. It writes nothing when that comment was written at or after
// STARTED, since Steward may have posted and then exited with 2, nor when
// the pull request's head is no longer HEAD: a newer run will post. A
// failure is a warning. Nothing from the pull request goes into the text
// but HEAD, checked to be a SHA.
//
// Reads PULL_REQUEST, HEAD, BUILD (the build step's outcome), STATUS (the
// Dangerfile's exit status), STARTED and SUMMARY_AUTHOR, and Actions'
// GITHUB_SERVER_URL, GITHUB_REPOSITORY and GITHUB_RUN_ID.
'use strict'

const os = require('node:os')

const marker = '<!-- steward-summary -->'

// Each value that reaches the API or the text, and what it has to match.
const formats = {
  PULL_REQUEST: /^[1-9][0-9]*$/,
  HEAD: /^([0-9a-f]{40}|[0-9a-f]{64})$/i,
  STARTED: /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/,
  GITHUB_SERVER_URL: /^https?:\/\/[^\s()<>[\]]+$/,
  GITHUB_REPOSITORY: /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/,
  GITHUB_RUN_ID: /^[0-9]+$/
}

// Why the run didn't report, as the end of a sentence.
function reason (build, status) {
  if (build === 'failure') return "the Dangerfile didn't build"
  if (!/^[0-9]+$/.test(status)) return 'the step that runs the Dangerfile ended without an exit status'
  const code = Number(status)
  if (code === 2) return "the Dangerfile exited with status 2, Steward's for a run it couldn't complete"
  // A shell reports a process a signal stopped as 128 plus its number.
  const signal = Object.keys(os.constants.signals).find(name => os.constants.signals[name] === code - 128)
  if (signal) return `the Dangerfile was stopped by ${signal} (status ${code})`
  return `the Dangerfile exited with status ${code}`
}

// The text after the marker line, which only the commit and the run vary.
function text (env) {
  const commit = env.HEAD.toLowerCase().slice(0, 7)
  const run = `${env.GITHUB_SERVER_URL.replace(/\/$/, '')}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
  return `**Steward didn't finish** on ${commit}: ${reason(env.BUILD, env.STATUS ?? '')}.

This commit hasn't been checked. The [workflow run](${run}) has the log.
`
}

// Whether `comment` is a summary comment by `author`: Steward compares the
// first line without a CR, as GitHub's web editor saves CRLF line endings.
function isSummary (comment, author) {
  const firstLine = (comment.body ?? '').split('\n', 1)[0].replace(/\r$/, '')
  return firstLine === marker && (comment.user?.login ?? '').toLowerCase() === author.toLowerCase()
}

module.exports = async ({ github, core, env = process.env }) => {
  const invalid = Object.keys(formats).filter(name => !formats[name].test(env[name] ?? ''))
  if (invalid.length > 0) {
    core.warning(`Steward didn't finish, but ${invalid.join(', ')} isn't set as expected, so the summary comment is left as it is.`, { title: 'Steward' })
    return 'skipped'
  }
  const [owner, repo] = env.GITHUB_REPOSITORY.split('/')
  const number = Number(env.PULL_REQUEST)
  const author = env.SUMMARY_AUTHOR || 'github-actions[bot]'
  const body = `${marker}\n${text(env)}`
  try {
    const comments = await github.paginate(github.rest.issues.listComments, { owner, repo, issue_number: number, per_page: 100 })
    const summary = comments.find(comment => isSummary(comment, author))
    if (summary && Date.parse(summary.updated_at) >= Date.parse(env.STARTED)) {
      core.info(`The summary comment ${summary.html_url} was written after this run started, so it's left as it is.`)
      return 'newer'
    }
    const { data: pull } = await github.rest.pulls.get({ owner, repo, pull_number: number })
    if (pull.head.sha.toLowerCase() !== env.HEAD.toLowerCase()) {
      core.info(`The pull request's head is ${pull.head.sha} now, not ${env.HEAD}, so the run for the newer commit posts the summary.`)
      return 'stale'
    }
    if (summary) {
      try {
        const { data } = await github.rest.issues.updateComment({ owner, repo, comment_id: summary.id, body })
        core.info(`Replaced the summary comment: ${data.html_url}`)
        return 'updated'
      } catch (error) {
        // Deleted since it was listed: a new one takes its place, as Steward does.
        if (error.status !== 404) throw error
      }
    }
    const { data } = await github.rest.issues.createComment({ owner, repo, issue_number: number, body })
    core.info(`Posted the summary comment: ${data.html_url}`)
    return 'created'
  } catch (error) {
    const advice = error.status === 403
      ? ' The token needs `pull-requests: write`; a pull request from a fork or Dependabot gets a read-only one.'
      : ''
    core.warning(`Steward didn't finish, and the summary comment, which may still show an earlier commit's findings, couldn't be replaced: ${error.message}.${advice}`, { title: 'Steward' })
    return 'failed'
  }
}
