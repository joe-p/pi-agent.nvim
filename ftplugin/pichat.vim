" pi.nvim chat buffer settings
" This file is sourced when editing files with pichat filetype

setlocal buftype=nofile
setlocal noswapfile
setlocal bufhidden=hide
setlocal nonumber
setlocal norelativenumber
setlocal signcolumn=no
setlocal wrap
setlocal linebreak
setlocal cursorline
" Easy quit
nnoremap <buffer> q <cmd>close<CR>

" Scroll to bottom
nnoremap G G

" Status line is set dynamically by chat.configure_window()