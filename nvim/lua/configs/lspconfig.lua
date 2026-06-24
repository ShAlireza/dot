local function setup_cmp()
  require("fidget").setup {}
  require("mason").setup()

  local lspconfig = require "lspconfig"

  lspconfig.pylsp.setup {
    settings = {
      pylsp = {
        plugins = {
          ruff = {
            enabled = true,
          },
        },
      },
    },
  }

  local cmp = require "cmp"
  local cmp_select = { behavior = cmp.SelectBehavior.Select }

  -- this is the function that loads the extra snippets to luasnip
  -- from rafamadriz/friendly-snippets
  require("luasnip.loaders.from_vscode").lazy_load()
  local luasnip = require "luasnip"

  local kind_icons = {
    Text = "󰊄",
    Method = "m",
    Function = "󰊕",
    Constructor = "",
    Field = "",
    Variable = "󰫧",
    Class = "󰝯",
    Interface = "",
    Module = "",
    Property = "",
    Unit = "",
    Value = "󰇼",
    Enum = "",
    Keyword = "",
    Snippet = "",
    Color = "",
    File = "",
    Reference = "",
    Folder = "",
    EnumMember = "",
    Constant = "ﲀ",
    Struct = "",
    Event = "",
    Operator = "",
    TypeParameter = "",
  }
  cmp.setup {
    sources = {
      { name = "path" },
      { name = "nvim_lsp" },
      { name = "luasnip", keyword_length = 2 },
      { name = "buffer", keyword_length = 3 },
      { name = "neorg" },
    },
    mapping = cmp.mapping.preset.insert {
      ["<C-p>"] = cmp.mapping.select_prev_item(cmp_select),
      ["<C-n>"] = cmp.mapping.select_next_item(cmp_select),
      -- ['<CR>'] = cmp.mapping.confirm({ select = true }),
      -- ['<C-Space>'] = cmp.mapping.complete(),
      ["<CR>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          if luasnip.expandable() then
            luasnip.expand()
          else
            cmp.confirm {
              select = true,
            }
          end
        else
          fallback()
        end
      end),

      ["<Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.locally_jumpable(1) then
          luasnip.jump(1)
        else
          fallback()
        end
      end, { "i", "s" }),

      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.locally_jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { "i", "s" }),
    },
    snippet = {
      expand = function(args)
        require("luasnip").lsp_expand(args.body)
      end,
    },
    formatting = {
      fields = { "kind", "abbr", "menu" },
      format = function(entry, vim_item)
        vim_item.kind = string.format("%s", kind_icons[vim_item.kind])
        vim_item.menu = ({
          nvim_lsp = "[LSP]",
          luasnip = "[Snippet]",
          buffer = "[Buffer]",
          path = "[Path]",
        })[entry.source.name]
        return vim_item
      end,
    },
  }
  require("lspconfig").terraformls.setup {}
  vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    pattern = { "*.tf", "*.tfvars" },
    callback = function()
      vim.lsp.buf.format()
    end,
  })
end

require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "clangd", "pylsp", "ruff", "terraformls" }
vim.lsp.enable(servers)

setup_cmp()

-- read :h vim.lsp.config for changing options of lsp servers
