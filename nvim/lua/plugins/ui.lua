return {
  {
    "folke/noice.nvim",
    opts = {
      lsp = {
        progress = {
          -- Disabled: stacks up multiple popups (e.g. pyright "Analyzing") that
          -- are distracting while typing.
          enabled = false,
        },
      },
    },
  },
}
