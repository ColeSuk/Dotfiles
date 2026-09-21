-- Languages without a LazyVim extra
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
        html = {},
        cssls = {},
        emmet_language_server = {},
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "shellcheck", "shfmt", "prettier" } },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "bash", "lua", "python", "php", "nginx", "dockerfile", "html", "css", "javascript" },
    },
  },
  -- Format web files with prettier
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        -- php-cs-fixer crashes without a composer.json unless rules are given explicitly
        php_cs_fixer = { args = { "fix", "--rules=@PSR12", "$FILENAME" } },
      },
      formatters_by_ft = {
        html = { "prettier" },
        css = { "prettier" },
        javascript = { "prettier" },
      },
    },
  },
}
