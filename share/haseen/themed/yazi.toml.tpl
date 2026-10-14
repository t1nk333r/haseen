# Rendered by `haseen theme set` into current/theme/yazi.toml, which
# ~/.config/yazi/theme.toml is a symlink to (seeds/66-yazi.sh). yazi merges
# this over its own preset, so only the styles a wrong palette would make
# unreadable are here.

[mgr]
cwd = { fg = "{{ accent }}" }

find_keyword  = { fg = "{{ yellow }}", bold = true, italic = true, underline = true }
find_position = { fg = "{{ magenta }}", bg = "reset", bold = true, italic = true }

symlink_target = { fg = "{{ muted }}", italic = true }

marker_copied   = { fg = "{{ green }}",  bg = "{{ green }}" }
marker_cut      = { fg = "{{ red }}",    bg = "{{ red }}" }
marker_marked   = { fg = "{{ cyan }}",   bg = "{{ cyan }}" }
marker_selected = { fg = "{{ yellow }}", bg = "{{ yellow }}" }

count_copied   = { fg = "{{ background }}", bg = "{{ green }}" }
count_cut      = { fg = "{{ background }}", bg = "{{ red }}" }
count_selected = { fg = "{{ background }}", bg = "{{ yellow }}" }

border_style = { fg = "{{ muted }}" }

[tabs]
active   = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
inactive = { fg = "{{ accent }}", bg = "{{ selection }}" }

[mode]
normal_main = { fg = "{{ background }}", bg = "{{ accent }}", bold = true }
normal_alt  = { fg = "{{ accent }}", bg = "{{ selection }}" }
select_main = { fg = "{{ background }}", bg = "{{ green }}", bold = true }
select_alt  = { fg = "{{ green }}", bg = "{{ selection }}" }
unset_main  = { fg = "{{ background }}", bg = "{{ red }}", bold = true }
unset_alt   = { fg = "{{ red }}", bg = "{{ selection }}" }

[status]
perm_sep   = { fg = "{{ muted }}" }
perm_type  = { fg = "{{ green }}" }
perm_read  = { fg = "{{ yellow }}" }
perm_write = { fg = "{{ red }}" }
perm_exec  = { fg = "{{ cyan }}" }

progress_label  = { fg = "{{ foreground }}", bold = true }
progress_normal = { fg = "{{ green }}", bg = "{{ background }}" }
progress_error  = { fg = "{{ yellow }}", bg = "{{ red }}" }

[which]
border          = { fg = "{{ accent }}" }
cand            = { fg = "{{ cyan }}" }
rest            = { fg = "{{ muted }}" }
desc            = { fg = "{{ magenta }}" }
separator_style = { fg = "{{ muted }}" }

[confirm]
border  = { fg = "{{ accent }}" }
title   = { fg = "{{ accent }}" }
list    = { fg = "{{ foreground }}" }
btn_yes = { fg = "{{ background }}", bg = "{{ accent }}" }
btn_no  = { fg = "{{ foreground }}" }

[pick]
border   = { fg = "{{ accent }}" }
active   = { fg = "{{ magenta }}", bold = true }
inactive = { fg = "{{ foreground }}" }

[input]
border   = { fg = "{{ accent }}" }
title    = { fg = "{{ foreground }}" }
value    = { fg = "{{ foreground }}" }
selected = { bg = "{{ selection }}" }

[cmp]
border   = { fg = "{{ accent }}" }
active   = { fg = "{{ magenta }}", bold = true }
inactive = { fg = "{{ foreground }}" }

[tasks]
border  = { fg = "{{ accent }}" }
title   = { fg = "{{ foreground }}" }
hovered = { fg = "{{ magenta }}", underline = true }

[help]
on      = { fg = "{{ magenta }}" }
run     = { fg = "{{ cyan }}" }
desc    = { fg = "{{ muted }}" }
hovered = { bg = "{{ selection }}", bold = true }
footer  = { fg = "{{ background }}", bg = "{{ foreground }}" }

[notify]
title_info  = { fg = "{{ green }}" }
title_warn  = { fg = "{{ yellow }}" }
title_error = { fg = "{{ red }}" }
