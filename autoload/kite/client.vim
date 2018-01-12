let s:port         = 46624
let s:channel_base = 'localhost:'.s:port
let s:base_url     = 'http://127.0.0.1:'.s:port
let s:editor_path  = '/clientapi/editor'
let s:hover_path   = '/api/buffer/vim'
let s:example_path = '/api/python/curation'
let s:webapp_path  = '/clientapi/desktoplogin?d='
let s:status_path  = '/clientapi/status?filename='
let s:user_path    = '/clientapi/user'
let s:symbol_report_path = '/api/editor/symbol'


function! kite#client#logged_in(handler)
  let path = s:user_path
  if has('channel')
    let response = s:internal_http(path, g:kite_short_timeout)
  else
    let response = s:external_http(s:base_url.path, g:kite_short_timeout)
  endif
  return a:handler(kite#client#parse_response(response))
endfunction


function! kite#client#status(filename, handler)
  let path = s:status_path.kite#utils#url_encode(a:filename)
  if has('channel')
    let response = s:internal_http(path, g:kite_short_timeout)
  else
    let response = s:external_http(s:base_url.path, g:kite_short_timeout)
  endif
  return a:handler(kite#client#parse_response(response))
endfunction


function! kite#client#webapp_link(id)
  call kite#utils#browse(s:base_url.s:webapp_path.kite#utils#url_encode('/docs/'.a:id))
endfunction


function! kite#client#example(id, handler)
  let path = s:example_path.'/'.a:id
  if has('channel')
    let response = s:internal_http(path, g:kite_long_timeout)
  else
    let response = s:external_http(s:base_url.path, g:kite_long_timeout)
  endif
  return a:handler(kite#client#parse_response(response))
endfunction


function! kite#client#hover(filename, hash, characters_start, characters_end, handler)
  let path = s:hover_path.'/'.a:filename.'/'.a:hash.'/hover?selection_begin_runes='.a:characters_start.'&selection_end_runes='.a:characters_end
  if has('channel')
    call s:async(function('s:timer_hover', [path, g:kite_long_timeout, a:handler]))
  else
    call kite#async#execute(s:external_http_cmd(s:base_url.path, g:kite_long_timeout), a:handler)
  endif
endfunction

function! s:timer_hover(path, timeout, handler, timer)
  call a:handler(kite#client#parse_response(s:internal_http(a:path, a:timeout)))
endfunction


function! kite#client#symbol_report(id, handler)
  let path = s:symbol_report_path.'/'.a:id
  if has('channel')
    call s:async(function('s:timer_hover', [path, g:kite_long_timeout, a:handler]))
  else
    call kite#async#execute(s:external_http_cmd(s:base_url.path, g:kite_long_timeout), a:handler)
  endif
endfunction


function! kite#client#signatures(json, handler)
  let path = s:editor_path.'/signatures'
  if has('channel')
    let response = s:internal_http(path, g:kite_long_timeout, a:json)
  else
    let response = s:external_http(s:base_url.path, g:kite_long_timeout, a:json)
  endif
  return a:handler(kite#client#parse_response(response))
endfunction


function! kite#client#completions(json, handler)
  let path = s:editor_path.'/completions'
  if has('channel')
    let response = s:internal_http(path, g:kite_long_timeout, a:json)
  else
    let response = s:external_http(s:base_url.path, g:kite_long_timeout, a:json)
  endif
  return a:handler(kite#client#parse_response(response))
endfunction


function! kite#client#post_event(json, handler)
  let path = s:editor_path.'/event'
  if has('channel')
    call s:async(function('s:timer_post_event', [path, g:kite_short_timeout, a:json, a:handler]))
  else
    call kite#async#execute(s:external_http_cmd(s:base_url.path, g:kite_short_timeout, a:json), a:handler)
  endif
endfunction

function! s:timer_post_event(path, timeout, json, handler, timer)
  call a:handler(kite#client#parse_response(s:internal_http(a:path, a:timeout, a:json)))
endfunction


function! s:async(callback)
  call timer_start(0, a:callback)
endfunction


" Optional argument is json to be posted
function! s:internal_http(path, timeout, ...)
  " Use HTTP 1.0 (not 1.1) to avoid having to parse chunked responses.
  if a:0
    let str = 'POST '.a:path." HTTP/1.0\nHost: localhost\nContent-Type: application/x-www-form-urlencoded\nContent-Length: ".len(a:1)."\n\n".a:1
  else
    let str = 'GET '.a:path." HTTP/1.0\nHost: localhost\n\n"
  endif
  call kite#utils#log(map(split(str, '\n', 1), '"> ".v:val'))


  let response = ''
  let response_content_length = -1
  let channel = ch_open(s:channel_base, {'mode': 'raw'})
  try
    call ch_sendraw(channel, str)
  catch /E906/
    return response
  endtry
  while v:true
    try
      let msg = ch_read(channel, {'timeout': a:timeout})
      if response_content_length == -1
        let response_content_length = kite#client#content_length(msg)
      endif
    catch /E906/
      " channel no longer available
      let msg = ''
    endtry
    if msg == ''
      call kite#utils#log('Timed out waiting for response')
      break
    else
      let response .= msg
      let response_length = kite#client#body_length(response)
      if response_length == response_content_length
        break
      endif
      call kite#utils#log('Incomplete response: received '.response_length.' bytes of '.response_content_length.' bytes. Waiting for more')
    endif
  endwhile
  return response
endfunction


" Optional argument is json to be posted
function! s:external_http(url, timeout, ...)
  if a:0
    let cmd = call(function('s:external_http_cmd'), [a:url, a:timeout] + a:000)
  else
    let cmd = s:external_http_cmd(a:url, a:timeout)
  endif
  return system(cmd)
endif
endfunction


" Optional argument is json to be posted
function! s:external_http_cmd(endpoint, timeout, ...)
  let cmd = s:http_binary
  let cmd .= ' --timeout '.a:timeout.'ms'
  if a:0
    if !empty(a:1)
      let cmd .= ' --post --data '
      if kite#utils#windows()
        let cmd .= s:win_escape_json(a:1)
      else
        let cmd .= s:shellescape(a:1)
      endif
    endif
  endif
  let cmd .= ' '.s:shellescape(a:endpoint)
  call kite#utils#log('> '.cmd)
  return cmd
endfunction


" Returns the integer HTTP response code and the string body in a dictionary.
"
" lines - either a list (from async commands) or a string (from sync)
function! kite#client#parse_response(lines)
  if type(a:lines) == v:t_string
    let lines = split(a:lines, '\r\?\n', 1)
  else
    let lines = a:lines
  endif
  call kite#utils#log(map(copy(lines), '"< ".v:val'))

  if empty(a:lines)
    return {'status': 0, 'body': ''}
  endif

  if type(a:lines) == v:t_string
    let lines = split(a:lines, '\r\?\n')
  else
    let lines = a:lines
  endif

  " Ignore occasional 100 Continue.
  let i = match(lines, '^HTTP/1.[01] [2345]\d\d ')
  if i == -1
    return {'status': 0, 'body': ''}
  endif
  let status = split(lines[i], ' ')[1]

  let sep = match(lines, '^$', i)
  let body = join(lines[sep+1:], "\n")

  return {'status': status, 'body': body}
endfunction


" Returns the value of the Content-Length HTTP header extracted
" from the text, or -1 if none found.
function! kite#client#content_length(text)
  let matches = matchlist(a:text, 'Content-Length: \(\d\+\)')
  if empty(matches)
    return -1
  else
    return str2nr(matches[1])
  endif
endfunction


" Returns the length in bytes of the entity-body of the HTTP
" response text, 0 for an empty body, or -1 if no body is found.
function! kite#client#body_length(text)
  let a = split(a:text, '\r\?\n\r\?\n', 1)
  if len(a) == 2
    return len(a[1])
  else
    return -1
  endif
endfunction


" Only used with NeoVim on not-Windows, in async jobs.
function! s:shellescape(str)
  let [_shell, &shell] = [&shell, 'sh']
  let escaped = shellescape(a:str)
  let &shell = _shell
  return escaped
endfunction


" Only used with NeoVim on Windows.
function! s:win_escape_json(str)
  " Literal " -> \"
  let a = escape(a:str, '"')
  " Literal \\" -> \\\"  (for double quotes escaped inside json property values)
  let b = substitute(a, '\\\\"', '\\\\\\"', 'g')
  return '"'.b.'"'
endfunction


let s:http_binary = kite#utils#lib('kite-http')

