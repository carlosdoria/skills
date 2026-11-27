/** Um texto da caixa de prompt guardado pelo mod, ou nada. */
export type PromptRewriterDraft = string | null

declare module 'claude-code' {
  interface PluginState {
    'prompt-rewriter': {
      /** Reescrever automaticamente cada prompt ao enviar. */
      auto: boolean
      /** Uma reescrita está em andamento. */
      busy: boolean
      /** O rascunho antes da última reescrita pelo botão, para Desfazer. */
      original: PromptRewriterDraft
      /** O texto que o botão escreveu por último, para o modo Auto não reescrever de novo. */
      rewritten: PromptRewriterDraft
    }
  }
}
