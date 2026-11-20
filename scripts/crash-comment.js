// Replaces a pull request's summary comment when the Dangerfile didn't
// finish, so that an earlier push's summary doesn't read as current beside
// a red check. action.yml runs it with actions/github-script, which needs
// no curl or jq: a swift container has neither. Returns what it did, the
// step's `result`.
//
// It finds the comment as Steward does: the oldest one by SUMMARY_AUTHOR
// (github-actions[bot] when that's empty) whose first line is the marker,
// through every page, and keeps the marker so the next run updates the same
// comment. It writes nothing when the pull request's head is no longer
// HEAD, since a newer run will post, nor when a summary comment was written
// since the Dangerfile started, since Steward may have posted and then
// exited with 2. A failure is a warning. Nothing from the pull request goes
// into the text but HEAD, checked to be a SHA, and STATUS, used only when
// it's all digits and written as a number, with the name of the signal it
// stands for, from node's own table, when it stands for one.
//
// Reads PULL_REQUEST, HEAD, BUILD (the build step's outcome), STATUS (the
// Dangerfile's exit status, empty when it didn't run), STARTED (when it
// started, in seconds since the epoch, empty when it didn't) and
// SUMMARY_AUTHOR, and Actions' GITHUB_SERVER_URL, GITHUB_REPOSITORY and
// GITHUB_RUN_ID.
'use strict'

const os = require('node:os')

const marker = '<!-- steward-summary -->'

// Each value that reaches the API or the text, and what it has to match.
const formats = {
  PULL_REQUEST: /^[1-9][0-9]*$/,
  HEAD: /^([0-9a-f]{40}|[0-9a-f]{64})$/i,
  STARTED: /^([0-9]+)?$/,
  GITHUB_SERVER_URL: /^https?:\/\/[^\s()<>[\]]+$/,
  GITHUB_REPOSITORY: /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/,
  GITHUB_RUN_ID: /^[0-9]+$/
}

// Why the run didn't report, as the end of a sentence.
function reason (build, status) {
  if (build === 'failure') return "the Dangerfile didn't build"
  if (!/^[0-9]+$/.test(status)) return 'the Action stopped before the Dangerfile ran'
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

// When the Dangerfile started, on GitHub's clock: GitHub's time now, from
// the `Date` header of `response`, less the time since `started` on the
// runner's clock, so the runner's offset cancels out. Both are cut to whole
// seconds, which only makes it earlier, so more comments count as newer.
// Without the header, the runner's clock.
function start (started, response, now) {
  const github = Date.parse(response.headers?.date ?? '')
  const runner = now()
  return (Number.isNaN(github) ? runner : github) - (runner - Number(started) * 1000)
}

module.exports = async ({ github, core, env = process.env, now = Date.now }) => {
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
    const summaries = comments.filter(comment => isSummary(comment, author))
    const pull = await github.rest.pulls.get({ owner, repo, pull_number: number })
    if (pull.data.head.sha.toLowerCase() !== env.HEAD.toLowerCase()) {
      core.info(`The pull request's head is ${pull.data.head.sha} now, not ${env.HEAD}, so the run for the newer commit posts the summary.`)
      return 'stale'
    }
    // Any of them: Steward posts a new one when the oldest was deleted.
    if (env.STARTED) {
      const started = start(env.STARTED, pull, now)
      const newer = summaries.find(comment => Date.parse(comment.updated_at) >= started)
      if (newer) {
        core.info(`The summary comment ${newer.html_url} was written since the Dangerfile started, so it's left as it is.`)
        return 'left'
      }
    }
    if (summaries.length > 0) {
      try {
        const { data } = await github.rest.issues.updateComment({ owner, repo, comment_id: summaries[0].id, body })
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
