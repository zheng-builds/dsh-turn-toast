// dsh-turn-notify — show a desktop toast when a turn finishes.
//
// The session log is the source of truth, but `session.events` is a
// subscription API rather than an array, so this plugin remembers the last
// assistant text it saw and uses it when `turn/end` arrives. The toast is
// drawn by lib/notify.ps1, which skips fullscreen apps and, optionally, the
// focused DSH window.

import { spawn } from 'node:child_process'
import { appendFileSync, mkdirSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'turn-notify'

const DEFAULTS = {
  enabled: true,
  seconds: 6,
  onlyWhenUnfocused: true,
  maxChars: 40,
  sound: true,
  soundFile: '',
}

const PLUGIN_DIR = dirname(fileURLToPath(import.meta.url))
const NOTIFY_SCRIPT = join(PLUGIN_DIR, 'lib', 'notify.ps1')
const BUNDLED_CHIME = join(PLUGIN_DIR, 'assets', 'notify.wav')
const TMP_DIR = join(tmpdir(), 'dsh-turn-notify')

function logLine(text) {
  try {
    mkdirSync(TMP_DIR, { recursive: true })
    const log = join(TMP_DIR, 'plugin.log')
    try {
      if (statSync(log).size > 256 * 1024) writeFileSync(log, '')
    } catch {}
    appendFileSync(log, `[${new Date().toISOString()}] ${text}\n`, 'utf8')
  } catch {}
}

function firstSentence(text, maxChars) {
  const flat = String(text)
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[#>*`_~[\]]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
  if (flat.length === 0) return ''
  const cut = flat.split(/(?<=[。！？!?；;])/)[0] || flat
  const sentence = cut.trim()
  return sentence.length > maxChars ? sentence.slice(0, maxChars) + '…' : sentence
}

function textOf(message) {
  const content = message?.content
  if (!Array.isArray(content)) return ''
  for (let i = content.length - 1; i >= 0; i--) {
    const block = content[i]
    if (block?.type === 'text' && typeof block.text === 'string' && block.text.trim() !== '') {
      return block.text
    }
  }
  return ''
}

function showToast(cfg, message) {
  try {
    mkdirSync(TMP_DIR, { recursive: true })
    const file = join(TMP_DIR, `msg-${process.pid}-${Date.now()}.txt`)
    writeFileSync(file, message, 'utf8')
    const args = [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-WindowStyle', 'Hidden',
      '-File', NOTIFY_SCRIPT,
      '-MessageFile', file,
      '-Seconds', String(cfg.seconds),
      '-Log', join(TMP_DIR, 'render.log'),
    ]
    if (cfg.onlyWhenUnfocused) args.push('-OnlyWhenUnfocused')
    if (cfg.sound === false) {
      args.push('-NoSound')
    } else {
      const configured = typeof cfg.soundFile === 'string' ? cfg.soundFile.trim() : ''
      const chime = configured !== '' ? configured : BUNDLED_CHIME
      args.push('-SoundFile', chime)
    }
    const child = spawn('powershell.exe', args, { stdio: 'ignore', windowsHide: true })
    child.on('error', (error) => logLine(`spawn error: ${error?.message ?? error}`))
    child.unref()
    logLine(`toast: ${message}`)
  } catch (error) {
    logLine(`toast error: ${error?.message ?? error}`)
  }
}

export function apply(ctx, rawConfig) {
  const cfg = { ...DEFAULTS, ...(rawConfig ?? {}) }
  if (cfg.enabled === false) return

  // sessionId -> { turn, text }, kept from `assistant/message` events.
  const lastText = new Map()

  const sessionKey = (session) => session?.header?.id ?? session?.id ?? 'unknown'

  const onEvent = (session, event) => {
    try {
      const key = sessionKey(session)
      const type = event?.type

      if (type === 'assistant/message') {
        const text = textOf(event?.data?.message)
        if (text) lastText.set(key, { turn: event?.data?.turn, text })
        return
      }

      if (type !== 'turn/end') return
      // Subagent sessions belong to a parent turn; the parent notifies.
      if (session?.header?.parentSessionId != null) return

      const turn = event?.data?.turn
      const kind = event?.data?.reason?.kind
      let text = ''
      const remembered = lastText.get(key)
      if (remembered && (remembered.turn === turn || turn === undefined)) text = remembered.text
      if (remembered) lastText.delete(key)

      const sentence = firstSentence(text, cfg.maxChars)
      const prefix = kind === 'completed' || kind === undefined ? '' : '（未完成）'
      const message = sentence === '' ? `任务已结束${prefix}` : sentence
      showToast(cfg, message)
    } catch (error) {
      logLine(`handler error: ${error?.message ?? error}`)
    }
  }

  ctx.effect(() => ctx.on('session/event', onEvent))
}
