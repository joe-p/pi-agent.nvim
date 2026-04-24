" pi.nvim input buffer settings
" This file is sourced when editing files with piinput filetype

setlocal buftype=acwrite
setlocal noswapfile
setlocal bufhidden=hide
setlocal nonumber
setlocal norelativenumber
setlocal signcolumn=no
setlocal wrap
setlocal linebreak
setlocal breakindent

" Show help in statusline
if &statusline ==# '' || &statusline =~# '%!'
  setlocal statusline=%{getline('.')==''?'Type\ message\ here...':''}
endif