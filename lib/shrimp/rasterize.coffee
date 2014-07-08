page = require('webpage').create()
fs = require('fs')
system = require('system')

args = {}
for i in [1..(system.args.length-1)] by 2
  args[system.args[i].replace(/^-/, '')] = system.args[i+1]

console.log(JSON.stringify(args));

margin = args.margin || '0cm'
orientation = args.orientation || 'portrait'
render_time = args.render_time || 10000 
cookies = {}

if args.cookies?
  try 
    f = fs.open(args.cookies, "r")
    cookies = JSON.parse(f.read())
    fs.remove(args.cookies)
  catch e
    console.log(e);
  
  phantom.cookiesEnabled = true
  phantom.cookies = cookies

page.viewportSize = { width:1200, height:1200 }
page.zoomFactor = args.zoom || 1.0
if args.clip_height?
  page.clipRect =
    left: 0
    top: 0
    width: page.viewportSize.width
    height: args.clip_height

if args.output_format == "pdf"
  paperSize =
    format: args.format
    orientation: orientation
    margin:margin

  if args.header?
    paperSize.header =
      height: args.header_height || "1cm"
      contents: phantom.callback (pageNum, numPages) ->
        fs.read(args.header).replace(/\[pageNum\]/, pageNum).replace(/\[numPages\]/, numPages)
  if args.footer?
    paperSize.footer =
      height: args.footer_height || "1cm"
      contents: phantom.callback (pageNum, numPages) ->
        fs.read(args.footer).replace(/\[pageNum\]/, pageNum).replace(/\[numPages\]/, numPages)
  
  page.paperSize = paperSize

# Determine the statusCode
statusCode = null
page.onResourceReceived = (resource) =>
  if resource.url == args.input
    statusCode = resource.status

# Don't accept gzipped responses to fix https://github.com/ariya/phantomjs/issues/10930
page.customHeaders =
  "Accept-Encoding": "identity"
  "X-Publishing": "true"
  
page.onError = (msg, trace) ->
  msgStack = ['ERROR: ' + msg]
  if trace && trace.length
    msgStack.push('TRACE:')
    trace.forEach (t) ->
      msgStack.push(' -> ' + t.file + ': ' + t.line + (t.function ? ' (in function "' + t.function + '")' : ''))
  console.error(msgStack.join('\n'))

page.open args.input, (status) =>
  if status != 'success' || (statusCode != 200 && statusCode != null)
    console.log(statusCode, 'Unable to load the address: ', args.input)
    phantom.exit(1);
  else
    window.setTimeout =>
        page.render(args.output)

        if args.html_output
          # Append the HTML content since the file is created by caller.
          fs.write(args.html_output, page.content, 'a')
      
        console.log("Rendered to: #{args.output}")
        phantom.exit();
      , render_time

