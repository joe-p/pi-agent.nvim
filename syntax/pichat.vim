" pi.nvim chat buffer syntax
if exists('b:current_syntax')
  finish
endif

" User message header
syntax match PiUserHeader "^┌─ User ─\+"
syntax match PiUserLine "^│ " contained
syntax match PiUserEnd "^└─\+"

" Assistant sections  
syntax match PiAssistantHeader "^┌─ Assistant ─\+"
syntax match PiAssistantEnd "^└─\+"
syntax match PiThinkingHeader "^┌─ Thinking ─\+"
syntax match PiThinkingLine "^│ " contained

" Tool sections
syntax match PiToolHeader "^╭─ Tool:\? \w\+\s*─\+"
syntax match PiToolEnd "^╰─\+"
syntax match PiToolCall "^╭─ Calling:\s\+\w\+"

" Status and info
syntax match PiInfo "^-- .* --$"
syntax match PiSpinner "^> .*"

" Error
syntax match PiErrorHeader "^┌─ Error ─\+"

" Markdown code blocks
syntax include @markdownCode syntax/markdown.vim
syntax region markdownCodeBlock start=/^│ ```\w*$/ end=/^│ ```$/ contains=@markdownCode

" Highlight Colors
highlight PiUserHeader ctermfg=Blue guifg=#7aa2f7 cterm=bold gui=bold
highlight PiUserLine ctermfg=Blue guifg=#7aa2f7
highlight PiUserEnd ctermfg=Blue guifg=#7aa2f7 cterm=bold gui=bold

highlight PiAssistantHeader ctermfg=Green guifg=#9ece6a cterm=bold gui=bold
highlight PiAssistantEnd ctermfg=Green guifg=#9ece6a cterm=bold gui=bold

highlight PiThinkingHeader ctermfg=Gray guifg=#565f89 cterm=italic gui=italic
highlight PiThinkingLine ctermfg=Gray guifg=#565f89 cterm=italic gui=italic

highlight PiToolHeader ctermfg=Magenta guifg=#bb9af7 cterm=bold gui=bold
highlight PiToolEnd ctermfg=Magenta guifg=#bb9af7 cterm=bold gui=bold
highlight PiToolCall ctermfg=Magenta guifg=#bb9af7 cterm=bold gui=bold

highlight PiInfo ctermfg=Cyan guifg=#7dcfff
highlight PiSpinner ctermfg=Yellow guifg=#e0af68

highlight PiErrorHeader ctermfg=Red guifg=#f7768e cterm=bold gui=bold

let b:current_syntax = 'pichat'