// Unit tests of scripts/crash-comment.js against a fake GitHub client:
// `node --test tests/*.test.js`. The Action's CI runs the script against
// GitHub too (.github/workflows/steward.yml and ci.yml).
'use strict'

const assert = require('node:assert/strict')
const os = require('node:os')
const { test } = require('node:test')
const replace = require('../scripts/crash-comment.js')

const head = 'c0ffee0123456789abcdef0123456789abcdef01'
const marker = '<!-- steward-summary -->'
// GitHub's time when it answers, and the runner's: the runner's clock is an
// hour fast, and the Dangerfile started ten seconds before the answer.
const answered = '2026-11-18T12:00:10Z'
const runnerNow = Date.parse(answered) + 3600 * 1000
const started = `${runnerNow / 1000 - 10}`
const env = {
  PULL_REQUEST: '7',
  HEAD: head,
  BUILD: 'success',
  STATUS: '2',
  STARTED: started,
  SUMMARY_AUTHOR: '',
  GITHUB_SERVER_URL: 'https://github.com',
  GITHUB_REPOSITORY: 'o/r',
  GITHUB_RUN_ID: '123'
}
const earlier = '2026-11-18T11:59:59Z'

function comment (id, { login = 'github-actions[bot]', body = `${marker}\n**1 failure** on 1234567`, updated = earlier } = {}) {
  return { id, user: { login }, body, updated_at: updated, html_url: `https://github.com/o/r/pull/7#issuecomment-${id}` }
}

// A client whose requests are recorded in `calls`; `fail` maps a request's
// name to the HTTP status it fails with.
function fake ({ comments = [], current = head, date = new Date(answered).toUTCString(), fail = {} } = {}) {
  const calls = []
  const request = (name, answer) => async params => {
    calls.push({ name, params })
    if (fail[name]) throw Object.assign(new Error(`HTTP ${fail[name]}`), { status: fail[name] })
    return { data: answer(params), headers: date === null ? {} : { date } }
  }
  const listComments = async () => assert.fail('listComments without paginate reads one page only')
  const github = {
    paginate: async (method, params) => {
      assert.equal(method, listComments)
      calls.push({ name: 'list', params })
      return comments
    },
    rest: {
      issues: {
        listComments,
        updateComment: request('update', ({ comment_id: id }) => ({ html_url: `#${id}` })),
        createComment: request('create', () => ({ html_url: '#new' }))
      },
      pulls: { get: request('pull', () => ({ head: { sha: current } })) }
    }
  }
  return { github, calls }
}

function logger () {
  const log = { info: [], warning: [] }
  return { log, core: { info: message => log.info.push(message), warning: message => log.warning.push(message) } }
}

async function run (overrides, client) {
  const { core, log } = logger()
  const result = await replace({ github: client.github, core, env: { ...env, ...overrides }, now: () => runnerNow })
  return { result, log, writes: client.calls.filter(call => call.name === 'update' || call.name === 'create') }
}

test('with no summary comment, it posts one that names the commit, says why, and links to the run', async () => {
  const client = fake({ comments: [comment(1, { body: 'A reviewer comment' })] })
  const { result, writes } = await run({ BUILD: 'failure', STATUS: '', STARTED: '' }, client)
  assert.equal(result, 'created')
  assert.deepEqual(writes.map(call => call.params.issue_number), [7])
  assert.equal(writes[0].params.body, `${marker}
**Steward didn't finish** on c0ffee0: the Dangerfile didn't build.

This commit hasn't been checked. The [workflow run](https://github.com/o/r/actions/runs/123) has the log.
`)
})

test('the text says how the Dangerfile ended', async t => {
  const sigill = os.constants.signals.SIGILL + 128
  const cases = [
    [{ BUILD: 'failure', STATUS: '', STARTED: '' }, "the Dangerfile didn't build."],
    [{ BUILD: 'skipped', STATUS: '', STARTED: '' }, 'the Action stopped before the Dangerfile ran.'],
    [{ STATUS: '2' }, "the Dangerfile exited with status 2, Steward's for a run it couldn't complete."],
    [{ STATUS: `${sigill}` }, `the Dangerfile was stopped by SIGILL (status ${sigill}).`],
    [{ STATUS: '3' }, 'the Dangerfile exited with status 3.'],
    [{ STATUS: '128' }, 'the Dangerfile exited with status 128.'],
    [{ STATUS: '2; rm -rf /' }, 'the Action stopped before the Dangerfile ran.']
  ]
  for (const [overrides, sentence] of cases) {
    await t.test(JSON.stringify(overrides), async () => {
      const { writes } = await run(overrides, fake())
      const line = writes[0].params.body.split('\n')[1]
      assert.match(line, /^\*\*Steward didn't finish\*\* on c0ffee0: /)
      assert.ok(line.endsWith(sentence), line)
    })
  }
})

test('it updates the oldest summary comment by the summary author, through every page', async () => {
  const client = fake({
    comments: [
      comment(1, { login: 'someone', body: `${marker}\nNot Steward's` }),
      comment(2, { body: `> ${marker}\nA quote of the summary` }),
      comment(3, { body: `Mentions\n${marker}` }),
      comment(4, { body: `${marker}x\nNot the marker line` }),
      comment(5, { body: `${marker}\r\nEdited on the web, so CRLF` }),
      comment(6)
    ]
  })
  const { result, writes } = await run({}, client)
  assert.equal(result, 'updated')
  assert.deepEqual(writes.map(call => [call.name, call.params.comment_id]), [['update', 5]])
  assert.equal(client.calls[0].params.per_page, 100)
})

test('summary-author picks whose comments count, ignoring case', async () => {
  const client = fake({ comments: [comment(1), comment(2, { login: 'Steward-App[bot]' })] })
  const { writes } = await run({ SUMMARY_AUTHOR: 'steward-app[bot]' }, client)
  assert.deepEqual(writes.map(call => call.params.comment_id), [2])
})

test('a summary comment written since the Dangerfile started, on GitHub\'s clock, is left alone', async t => {
  // The Dangerfile started at 12:00:00 on GitHub's clock.
  const cases = [
    ['the oldest, at the start', [comment(1, { updated: '2026-11-18T12:00:00Z' })], 'left'],
    ['a newer one, after it', [comment(1), comment(2, { updated: '2026-11-18T12:00:05Z' })], 'left'],
    ['the oldest, a second before', [comment(1, { updated: '2026-11-18T11:59:59Z' })], 'updated']
  ]
  for (const [name, comments, expected] of cases) {
    await t.test(name, async () => {
      const client = fake({ comments })
      const { result, writes, log } = await run({}, client)
      assert.equal(result, expected)
      if (expected === 'left') {
        assert.deepEqual(writes, [])
        assert.match(log.info[0], /written since the Dangerfile started/)
      }
    })
  }
})

test('without the Date header, the runner\'s clock decides', async () => {
  // On the runner's clock, an hour fast, the Dangerfile started at 13:00:00.
  const client = fake({ comments: [comment(1, { updated: '2026-11-18T12:30:00Z' })], date: null })
  assert.equal((await run({}, client)).result, 'updated')
  const after = fake({ comments: [comment(1, { updated: '2026-11-18T13:00:00Z' })], date: null })
  assert.equal((await run({}, after)).result, 'left')
})

test('when the Dangerfile didn\'t start, no comment counts as newer', async () => {
  const client = fake({ comments: [comment(1, { updated: '2026-11-18T12:00:09Z' })] })
  const { result } = await run({ BUILD: 'failure', STATUS: '', STARTED: '' }, client)
  assert.equal(result, 'updated')
})

test('when the head moved on, it writes nothing', async () => {
  const client = fake({ comments: [comment(1)], current: 'feedface'.repeat(5) })
  const { result, writes, log } = await run({}, client)
  assert.equal(result, 'stale')
  assert.deepEqual(writes, [])
  assert.match(log.info[0], /^The pull request's head is feedface/)
})

test('the head is compared ignoring case', async () => {
  const { result } = await run({ HEAD: head.toUpperCase() }, fake())
  assert.equal(result, 'created')
})

test('a summary comment deleted since it was listed is posted anew', async () => {
  const client = fake({ comments: [comment(1)], fail: { update: 404 } })
  const { result, writes } = await run({}, client)
  assert.equal(result, 'created')
  assert.deepEqual(writes.map(call => call.name), ['update', 'create'])
})

test('a read-only token gets a warning, and nothing throws', async () => {
  for (const comments of [[], [comment(1)]]) {
    const client = fake({ comments, fail: { create: 403, update: 403 } })
    const { result, log } = await run({}, client)
    assert.equal(result, 'failed')
    assert.equal(log.warning.length, 1)
    assert.match(log.warning[0], /couldn't be replaced: HTTP 403\. The token needs `pull-requests: write`/)
  }
})

test('any other failure is a warning too', async () => {
  const { result, log } = await run({}, fake({ fail: { pull: 500 } }))
  assert.equal(result, 'failed')
  assert.match(log.warning[0], /couldn't be replaced: HTTP 500\.$/)
})

test('a value that is not as expected stops it before any request', async t => {
  const cases = [
    { HEAD: 'main' },
    { HEAD: `${head}\nInjected` },
    { HEAD: head.slice(0, 39) },
    { PULL_REQUEST: '0' },
    { PULL_REQUEST: '7/../8' },
    { STARTED: '2026-11-18T12:00:00Z' },
    { GITHUB_SERVER_URL: 'https://github.com) [x](https://example.com' },
    { GITHUB_REPOSITORY: 'o/r/x' },
    { GITHUB_RUN_ID: '123abc' }
  ]
  for (const overrides of cases) {
    await t.test(JSON.stringify(overrides), async () => {
      const client = fake()
      const { result, log } = await run(overrides, client)
      assert.equal(result, 'skipped')
      assert.deepEqual(client.calls, [])
      assert.match(log.warning[0], new RegExp(`but ${Object.keys(overrides)[0]} isn't set as expected`))
    })
  }
})

test('a 64-character SHA, as a SHA-256 repository has, is accepted', async () => {
  const sha256 = 'ab'.repeat(32)
  const client = fake({ current: sha256 })
  const { result, writes } = await run({ HEAD: sha256 }, client)
  assert.equal(result, 'created')
  assert.match(writes[0].params.body, /on abababa: /)
})
