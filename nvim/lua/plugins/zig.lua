return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      zls = {
        mason = false,
        cmd = { vim.fn.expand("~/.local/bin/zls") },
      },
    },
  },
}
