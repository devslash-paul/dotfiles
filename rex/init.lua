-- Claude Code popup, the Rex version of the tmux display-popup binding.
-- ctrl+b then ctrl+c opens Claude in a floating pane over the current window.
-- Pressing it again while the popup has focus hides it. The pane is detached,
-- not closed, so Claude keeps running and the next press brings it back.
local terminal = "com.superlogical.terminal"
local POPUP_LABEL = "claude-popup"
local POPUP_BOUNDS = { 0.1, 0.1, 0.8, 0.8 }

local function find_popup()
  local res, err = rex.session.list_blocks{}
  if err ~= nil then
    error(err, 0)
  end
  for _, b in ipairs(res.blocks) do
    if b.label == POPUP_LABEL then
      return b
    end
  end
  return nil
end

-- The terminal reports its directory as file://HOST/path.
local function block_cwd(block_id)
  if block_id == nil then
    return nil
  end
  local res = rex.block.call(terminal, "pwd", { block_id = block_id })
  if res == nil or res.pwd == nil then
    return nil
  end
  return res.pwd:match("^file://[^/]*(/.*)$")
end

local function open_popup(ctx)
  local _, err = rex.session.new_layer{
    bounds = POPUP_BOUNDS,
    focus = true,
    layout = rex.layout.block{
      flavor = terminal .. ".shell",
      label = POPUP_LABEL,
      options = {
        -- An interactive zsh reads .zshrc, so PATH and aliases match a normal terminal.
        -- When Claude exits, the popup drops to a shell instead of closing.
        command = { "zsh", "-ic", "claude; exec zsh" },
        cwd = block_cwd(ctx.block_id),
      },
    },
  }
  if err ~= nil then
    error(err, 0)
  end
end

local function show_popup(ctx, popup)
  local _, err = rex.session.move_block{
    block_id = popup.block_id,
    anchor_block_id = ctx.block_id,
  }
  if err ~= nil then
    error(err, 0)
  end
  _, err = rex.session.float_block{ block_id = popup.block_id, bounds = POPUP_BOUNDS }
  if err ~= nil then
    error(err, 0)
  end
  rex.session.focus_block{ block_id = popup.block_id }
end

rex.action{
  name = "claude_popup",
  title = "Toggle Claude Popup",
  description = "Open Claude Code in a floating pane, or hide it if it has focus.",
  run = function(ctx, args)
    local popup = find_popup()
    if popup == nil then
      open_popup(ctx)
    elseif popup.placement ~= "placed" then
      show_popup(ctx, popup)
    elseif ctx.block_id == popup.block_id then
      rex.session.detach_block{ block_id = popup.block_id }
    else
      rex.session.focus_block{ block_id = popup.block_id }
    end
  end,
}

rex.bind("ctrl+b>ctrl+c", "claude_popup")

-- Leave Cmd+Alt+Left/Right to Rectangle (left half / right half).
rex.unbind("cmd+alt+left")
rex.unbind("cmd+alt+right")

-- Alt+h/j/k/l moves focus between panes, vim style.
rex.bind("alt+h", "pane.focus.left")
rex.bind("alt+j", "pane.focus.down")
rex.bind("alt+k", "pane.focus.up")
rex.bind("alt+l", "pane.focus.right")
