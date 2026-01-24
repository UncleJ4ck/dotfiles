return {
  {
    "nvim-mini/mini.base16",
    version = "*",
    lazy = false,
    priority = 10000,
    init = function()
      vim.o.termguicolors = true
    end,
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "matugen",
    },

    init = function()
      local uv = vim.uv or vim.loop
      if not uv or not uv.new_fs_event then
        return
      end

      local colors_dir = vim.fn.stdpath("config") .. "/colors"
      local target = "matugen.lua"
      vim.fn.mkdir(colors_dir, "p")

      if package.loaded._matugen_watch then
        return
      end

      local function safe_reload()
        pcall(vim.cmd.colorscheme, "matugen")
      end

      local timer = uv.new_timer()
      local function debounce_reload()
        timer:stop()
        timer:start(80, 0, function()
          vim.schedule(safe_reload)
        end)
      end

      local handle = uv.new_fs_event()
      handle:start(colors_dir, {}, function(filename, _events)
        -- Some systems send nil filename; reload anyway.
        if not filename then
          debounce_reload()
          return
        end

        if filename == target or filename:sub(-#target) == target then
          debounce_reload()
        end
      end)

      package.loaded._matugen_watch = { handle = handle, timer = timer }
    end,
  },
}
