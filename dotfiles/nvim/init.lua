-- ── bootstrap lazy.nvim ───────────────────────────────────────────────────────

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── options ───────────────────────────────────────────────────────────────────

vim.g.mapleader      = " "
vim.g.maplocalleader = " "

local opt            = vim.opt
opt.number           = true
opt.relativenumber   = true
opt.signcolumn       = "yes"
opt.tabstop          = 2
opt.shiftwidth       = 2
opt.expandtab        = true
opt.smartindent      = true
opt.wrap             = false
opt.cursorline       = true
opt.termguicolors    = true
opt.scrolloff        = 8
opt.sidescrolloff    = 8
opt.splitbelow       = true
opt.splitright       = true
opt.ignorecase       = true
opt.smartcase        = true
opt.updatetime       = 250
opt.timeoutlen       = 300
opt.undofile         = true
opt.clipboard        = "unnamedplus"
opt.conceallevel     = 1 -- for Obsidian.nvim and markdown

-- ── keymaps ───────────────────────────────────────────────────────────────────

local map            = vim.keymap.set

-- window navigation: <C-hjkl> is handled by smart-splits.nvim (configured below),
-- which moves between nvim splits and crosses into adjacent WezTerm panes at the edge.

-- buffer nav
map("n", "<S-h>", ":bprevious<CR>", { silent = true })
map("n", "<S-l>", ":bnext<CR>", { silent = true })

-- keep selection after indent
map("v", "<", "<gv")
map("v", ">", ">gv")

-- move selected lines
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- clear search highlight
map("n", "<Esc>", ":noh<CR>", { silent = true })

-- file tree
map("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle file tree" })

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Buffers" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>", { desc = "Recent files" })
map("n", "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", { desc = "Symbols" })

-- LSP (wired per-buffer in on_attach below)
map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
map("n", "gr", "<cmd>Telescope lsp_references<CR>", { desc = "References" })
map("n", "K", vim.lsp.buf.hover, { desc = "Hover docs" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Prev diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })

-- ── plugins ───────────────────────────────────────────────────────────────────

require("lazy").setup({

  -- colorscheme
  {
    "catppuccin/nvim",
    name     = "catppuccin",
    priority = 1000,
    opts     = {
      flavour                = "mocha",
      transparent_background = false,
      integrations           = {
        nvimtree    = true,
        telescope   = { enabled = true },
        treesitter  = true,
        cmp         = true,
        gitsigns    = true,
        lsp_trouble = true,
        which_key   = true,
      },
    },
    config   = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- status line
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme                = "catppuccin-mocha", -- catppuccin renamed its lualine themes per-flavour; "catppuccin" no longer exists
        globalstatus         = true,
        component_separators = { left = "", right = "" },
        section_separators   = { left = "", right = "" },
      },
    },
  },

  -- file tree
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      sort_by  = "case_sensitive",
      view     = { width = 30 },
      renderer = { group_empty = true },
      filters  = { dotfiles = false },
    },
  },

  -- fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    branch       = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config       = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          file_ignore_patterns = { "node_modules", ".git/", ".DS_Store" },
        },
      })
      telescope.load_extension("fzf")
    end,
  },

  -- treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master", -- pin to classic API; default branch is now the `main` rewrite (no .configs)
    build  = ":TSUpdate",
    opts   = {
      ensure_installed = {
        "lua", "vim", "vimdoc",
        "typescript", "javascript", "tsx", "kotlin", "html", "css",
        "python", "go", "rust",
        "json", "yaml", "toml", "markdown", "markdown_inline",
        "bash", "dockerfile",
      },
      highlight        = { enable = true },
      indent           = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },

  -- pane navigation: nvim splits <-> WezTerm panes (preserve-shell-keys mode)
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    config = function()
      local ss = require("smart-splits")
      ss.setup({ at_edge = "stop" })
      vim.keymap.set("n", "<C-h>", ss.move_cursor_left, { desc = "Move to left split/pane" })
      vim.keymap.set("n", "<C-j>", ss.move_cursor_down, { desc = "Move to lower split/pane" })
      vim.keymap.set("n", "<C-k>", ss.move_cursor_up, { desc = "Move to upper split/pane" })
      vim.keymap.set("n", "<C-l>", ss.move_cursor_right, { desc = "Move to right split/pane" })
      vim.keymap.set("n", "<M-h>", ss.resize_left, { desc = "Resize split left" })
      vim.keymap.set("n", "<M-j>", ss.resize_down, { desc = "Resize split down" })
      vim.keymap.set("n", "<M-k>", ss.resize_up, { desc = "Resize split up" })
      vim.keymap.set("n", "<M-l>", ss.resize_right, { desc = "Resize split right" })
    end,
  },

  -- WezTerm Lua API types: completion/docs when editing wezterm.lua
  {
    "folke/lazydev.nvim",
    ft = "lua",
    dependencies = { "DrKJeff16/wezterm-types" },
    opts = {
      library = {
        { path = "wezterm-types", mods = { "wezterm" } },
      },
    },
  },

  -- LSP
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      require("mason").setup()

      -- Buffer-local LSP keymaps — replaces the old per-server on_attach.
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local bufopts = { noremap = true, silent = true, buffer = args.buf }
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
          vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, bufopts)
        end,
      })

      -- Per-server overrides, merged over nvim-lspconfig's bundled lsp/ defaults.
      -- Registered before enabling so the override is in place when the server starts.
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace   = { library = vim.api.nvim_get_runtime_file("", true) },
          },
        },
      })

      local servers = {
        "lua_ls", "ts_ls", "pyright", "gopls", "rust_analyzer",
        "cssls", "html", "jsonls", "yamlls",
      }
      -- Auto-install all except servers that need a language toolchain the kit
      -- doesn't bundle (gopls installs via `go install` → needs Go). Those still
      -- get enabled below; install them with :MasonInstall after adding the toolchain.
      local auto = vim.tbl_filter(function(s) return s ~= "gopls" end, servers)
      require("mason-lspconfig").setup({ ensure_installed = auto })

      -- nvim 0.11+ native enable; consumes nvim-lspconfig's lsp/<name>.lua configs.
      vim.lsp.enable(servers)
    end,
  },

  -- autocompletion
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<Tab>"]     = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"]   = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }, {
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },

  -- formatter
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua        = { "stylua" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        tsx        = { "prettier" },
        css        = { "prettier" },
        html       = { "prettier" },
        json       = { "prettier" },
        yaml       = { "prettier" },
        markdown   = { "prettier" },
        python     = { "black" },
        go         = { "gofmt" },
        rust       = { "rustfmt" },
        sh         = { "shfmt" },
      },
      format_on_save = { timeout_ms = 500, lsp_fallback = true },
    },
  },

  -- git decorations
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add          = { text = "│" },
        change       = { text = "│" },
        delete       = { text = "󰍵" },
        topdelete    = { text = "‾" },
        changedelete = { text = "~" },
        untracked    = { text = "│" },
      },
    },
  },

  -- git UI
  {
    "NeogitOrg/neogit",
    dependencies = { "nvim-lua/plenary.nvim", "sindrets/diffview.nvim" },
    keys = {
      { "<leader>gg", "<cmd>Neogit<CR>", desc = "Neogit" },
    },
    opts = {},
  },

  -- autopairs
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  -- comments
  { "numToStr/Comment.nvim", opts = {} },

  -- which-key (keymap helper)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts  = {},
  },

  -- indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      indent = { char = "│" },
      scope  = { enabled = true },
    },
  },

  -- markdown preview (opens in browser)
  {
    "iamcco/markdown-preview.nvim",
    cmd   = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = function() vim.fn["mkdp#util#install"]() end,
    ft    = { "markdown" },
    keys  = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview" },
    },
  },

}, {
  -- lazy.nvim UI colors
  ui = {
    border = "rounded",
  },
})
