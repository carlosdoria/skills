import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'prompt-rewriter',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 9 },
    view: {},
  },
} as const

const USAGE = { input_tokens: 10, output_tokens: 10 } as never

test('a faixa mostra Prompt e Auto, no terminal e no desktop', async ($, on) => {
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })

    expect((await ui.find({ key: 'prompt' }))?.text).toBe('Prompt')
    expect((await ui.find({ key: 'auto' }))?.text).toBe('Auto: desligado')
    expect(await ui.find({ key: 'undo' })).toBe(undefined)
    await ui.unmount()
  }
})

test('Prompt reescreve o rascunho na caixa, e Desfazer volta', async ($, on) => {
  let box = 'arruma o bug do login q quebra qnd a senha tem acento'
  let asked = ''

  on('prompt.read', () => ({ value: { text: box, cursor: box.length } }))
  on('prompt.fill', (_, e) => {
    box = e.text
    return { isFilled: true }
  })
  on('session.messages', () => ({ value: [] }))
  on('model.complete', (_, e) => {
    asked = String(e.prompt)
    return {
      value: {
        isAnswered: true,
        text: '```\nCorrija o bug do login que quebra quando a senha tem acento.\n```',
        usage: USAGE,
      },
    }
  })
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))

  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  await ui.press({ key: 'prompt' })

  expect(asked).toContain('arruma o bug do login')
  expect(box).toBe('Corrija o bug do login que quebra quando a senha tem acento.')
  expect((await ui.find({ key: 'undo' }))?.text).toBe('Desfazer')

  await ui.press({ key: 'undo' })
  expect(box).toBe('arruma o bug do login q quebra qnd a senha tem acento')
  expect(await ui.find({ key: 'undo' })).toBe(undefined)
  await ui.unmount()
})

test('se o modelo falhar, o rascunho fica como estava', async ($, on) => {
  let box = 'refatora o módulo de pagamentos'
  let toast = ''

  on('prompt.read', () => ({ value: { text: box, cursor: box.length } }))
  on('prompt.fill', (_, e) => {
    box = e.text
    return { isFilled: true }
  })
  on('session.messages', () => ({ value: [] }))
  on('model.complete', () => ({
    value: { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage: USAGE } as never,
  }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', (_, e) => {
    toast = e.text
    return { value: undefined }
  })

  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  await ui.press({ key: 'prompt' })

  expect(box).toBe('refatora o módulo de pagamentos')
  expect(toast).toContain('529')
  expect((await ui.find({ key: 'prompt' }))?.text).toBe('Prompt')
  await ui.unmount()
})

test('Auto liga, é guardado, e não reescreve prompts de outros plugins', async ($, on) => {
  const stored: Record<string, unknown> = {}
  let sent = ''
  let calls = 0

  on('store.set', (_, e) => {
    stored[e.key] = e.value
    return { value: undefined }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('model.complete', () => {
    calls += 1
    return { value: { isAnswered: true, text: 'reescrito', usage: USAGE } }
  })
  on('prompt.submit', (_, e) => {
    sent = e.text
    return { text: e.text }
  })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'auto' })

  expect(stored.auto).toBe(true)
  expect((await ui.find({ key: 'auto' }))?.text).toBe('Auto: ligado')

  const plugin = { kind: 'plugin', name: 'outro' } as const
  await $.prompt.submit({ text: 'um prompt mandado por outro plugin, longo o bastante', wait: false, origin: plugin })
  expect(sent).toBe('um prompt mandado por outro plugin, longo o bastante')
  expect(calls).toBe(0)

  const person = { kind: 'composer' } as const
  await $.prompt.submit({ text: 'ok', wait: false, origin: person })
  expect(sent).toBe('ok')
  expect(calls).toBe(0)

  await $.prompt.submit({ text: 'cria testes pro serviço de checkout', wait: false, origin: person })
  expect(sent).toBe('reescrito')
  expect(calls).toBe(1)
  await ui.unmount()
})

test('no Auto, se o modelo falhar o prompt vai como foi escrito', async ($, on) => {
  let sent = ''

  on('store.get', () => ({ value: true }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('model.complete', () => ({
    value: { isAnswered: false, reason: 'empty-reply', usage: USAGE } as never,
  }))
  on('prompt.submit', (_, e) => {
    sent = e.text
    return { text: e.text }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.prompt.submit({
    text: 'cria testes pro serviço de checkout',
    wait: false,
    origin: { kind: 'sdk' },
  })
  expect(sent).toBe('cria testes pro serviço de checkout')
})
