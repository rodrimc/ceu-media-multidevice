
if not arg[1] then
  print ('Error: no input source specified')
  return
end

if not arg[2] then
  print ('Error: no prog file specified')
  return
end

local CODE_TEMPLATE =
  'code/await Emit_{#1}_Event ({#2}) -> none\ndo\n' ..
    '\tawait async ({#3}) do\n'                     ..
    '\t\temit {#4} ({#5});\n'                       ..
    '\tend\n'                                       ..
  'end'

local f = io.open (arg[1], 'r')
local maestro_src = f:read ('*all')
f:close()

lines = io.lines (arg[2])
input_evts = {}
output_evts = {}

for line in io.lines (arg[2]) do
  line = line:gsub("^%s*(.-)%s*$", "%1")
  if line:sub (1, 5) == 'input' then
    table.insert (input_evts, {})
    input_evts[#input_evts] =
      {
        line = line,
        args = {},
        evt = '',
        emitter = ''
      }
  elseif line:sub (1, 6) == 'output' then
    table.insert (output_evts, {})
    output_evts[#output_evts] =
      {
        line = line,
        args = {},
        evt = ''
      }
  end
end


function get_args (str)
  return str:match ("%((.-)%)")
end

function get_evt (str)
  return str:match ("%).-$"):sub(2):gsub("^%s*(.-)%s*;$", "%1")
end

function get_params(str, args)
  local params = ''
  if str == 'none' then
    params = str
  else
    local k = 1
    for arg in str:gmatch('([^,]+)') do
      arg = arg:gsub("^%s*(.-)%s*$", "%1")
      table.insert(args, arg)
      params = params .. 'var ' .. arg .. ' arg' .. k .. ', '
      k = k + 1
    end
    params = params:sub (1, -3)
  end
  return params
end

local STRUCT_TEMPLATE = 
  '\ttypedef struct {\n' ..
  '{#1}'               ..
  '\t} {#2};'

local UNION_TEMPLATE = 
  '\ttypedef union {\n' ..
  '{#1}'               ..
  '\t} u_args;'

local IF_OUTPUT_CALLBACK_TEMPLATE = 
  '\t\t\t\tif (p1.num == CEU_OUTPUT_{#1})\n' ..
  '\t\t\t\t{\n'                              ..
  '\t\t\t\t\ttype = "{#1}";\n'               ..
  '\t\t\t\t\tp.{#2} = *({#1}*) p2.ptr;\n'    ..
  '\t\t\t\t}'

local IF_OUTPUT_EVERY_TEMPLATE = 
  '\tif call Has_Mapping ("{#1}", &role, true) then\n'                                    ..
  '\t\t\t\t\t\tbuffer = [] .. [[ pack("{#1}",{#2}) ]];\n'                                 ..
  '\t\t\t\t\t\tspawn Client_Send_Message (&client.stub, &buffer) in send_message_pool;\n' ..
  '\t\t\t\t\tend'

local if_indent = '\t\t\t\t'
local every_indent = '\t\t\t'

-- OUTPUT
local OUTPUT_TO_GEN = ''
local IF_TO_GEN = ''
local OUTPUT_HANDLE_TO_GEN = ''

local union_fields = ''

local cond = '_strcmp(type, "{#1}") == 0 then\n'

for i = 1, #output_evts do
  local output = output_evts[i].line
  output = output:sub (7):gsub("^%s*(.-)%s*$", "%1")

  local args = get_args(output)
  local evt  = get_evt(output)
  local params = get_params (args, output_evts[i].args)

  --struct
  local struct_body = ''

  --set 'type' and 'u_args' variables
  IF_TO_GEN = IF_TO_GEN .. IF_OUTPUT_CALLBACK_TEMPLATE:gsub ('{#1}', evt):
                                                       gsub ('{#2}', evt:lower()) .. '\n'

  --every
  local every_body
  local indent = '\t\t\t\t'
  local if_statement
  local if_vars = ''
  local if_assignments = ''
  local if_body = IF_OUTPUT_EVERY_TEMPLATE:gsub ('{#1}', evt)
  local if_luavarlist = ''
  
  if i == 1 then
    if_statement = '\t\tif '
  else
    if_statement = '\t\telse/if '
  end
  every_body = '\t\t' .. if_statement .. cond:gsub ('{#1}', evt)

  for j = 1, #output_evts[i].args do
    local varname = 'arg' .. j
    local decl = '\t\t'  .. output_evts[i].args[j] .. ' ' .. varname .. ';\n'
    
    --body of structures (each per output event)
    struct_body = struct_body .. decl

    --body of ifs within the `every` handle (each per output event)
    decl = indent .. '\tvar ' .. output_evts[i].args[j] .. ' ' .. varname .. ';\n'
    if_vars = if_vars .. decl

    --assign the value passed in the event to each variable
    local assignment = indent .. '\t' .. varname .. ' = ' .. 'args.' .. evt:lower() .. '.arg' .. j 
    if_assignments = if_assignments  .. assignment .. ';\n' 

    --arguments to the 'pack' function
    if_luavarlist = if_luavarlist .. '@' .. varname .. ','
  end
  if if_luavarlist == '' then
    if_luavarlist = '{}'
  else
    if_luavarlist = if_luavarlist:sub(1, -2)
  end

  if_body = if_body:gsub ('{#2}', if_luavarlist)

  every_body = every_body .. if_vars .. if_assignments .. indent .. if_body .. '\n'

  local struct = STRUCT_TEMPLATE:gsub ('{#1}', struct_body):gsub('{#2}', evt)
  union_fields = union_fields .. '\t\t' .. evt .. ' ' .. evt:lower() .. ';\n' 

  OUTPUT_TO_GEN = OUTPUT_TO_GEN .. struct .. '\n\n'
  OUTPUT_HANDLE_TO_GEN = OUTPUT_HANDLE_TO_GEN .. every_body 
end

if OUTPUT_HANDLE_TO_GEN ~= '' then
  OUTPUT_HANDLE_TO_GEN = OUTPUT_HANDLE_TO_GEN .. '\t\t\t\tend'
end

OUTPUT_TO_GEN = OUTPUT_TO_GEN .. UNION_TEMPLATE:gsub ('{#1}', union_fields)

-- INPUT 
local INPUT_TO_GEN = ''
INPUT_TO_GEN = '/*'                                                       ..
          '\n * This excerpt of code is automatically generated by Mars.' ..
          '\n * Do not edit it.'                                          ..
          '\n */\n\n'

for i=1, #input_evts do
  local input = input_evts[i].line
  input = input:sub (5):gsub("^%s*(.-)%s*$", "%1")

  local args = get_args (input)
  local evt  = get_evt (input)
  local code_name = evt:lower():gsub('_.', string.upper):gsub('^.', string.upper)
  local code = string.gsub (CODE_TEMPLATE, '{#1}', code_name)
  local params = get_params (args, input_evts[i].args) 

  code = code:gsub ('{#2}', params)

  params = params:gsub ('(var .-).- ,-', '')
  if params == 'none' then
    params = '_'
  end

  code = code:gsub ('{#3}', params)
  code = code:gsub ('{#4}', evt)

  if params == '_' then
    params = ''
  end
  code = code:gsub ('{#5}', params)

  input_evts[i].evt = evt
  input_evts[i].emitter = 'Emit_' .. code_name .. '_Event';

  INPUT_TO_GEN = INPUT_TO_GEN .. code .. '\n'
end

CODE_TEMPLATE = '\n'                                                 ..
  'code/await Handle_Mapping (var _char&& mapping) -> none\n'        ..
  'do\n'                                                             ..
  '\tvar Exception.Lua? e;\n'                                        ..
  '\tcatch e do\n'                                                   ..
  '\t{#1}\n'                                                         ..
  '\tend\n'                                                          ..
  '\tif e? then\n'                                                   ..
  '\t\t_fprintf (_stderr, "[Mapping error:] %%s\\n", e!.message);\n' ..
  '\tend\n'                                                          ..
  'end'

code = ''

cond = '_strcmp(mapping, "{#1}") == 0'
for i = 1, #input_evts do
  input = input_evts[i]

  local statement
  if i == 1 then
    statement = '\tif '
  else
    statement = '\telse/if '
  end

  code = code .. statement .. ' ' .. cond:gsub('{#1}', input.evt) .. ' then\n'

  local body = ''
  local params = ''
  local attrs = ''
  local mapping_args = ''
  local ident = '\t\t\t'
  for j = 1, #input.args do
    local varname = 'arg' .. j
    local vardecl = 'var ' .. input.args[j] .. ' ' .. varname
    body = body .. ident .. vardecl .. ' = _;\n'
    params = params .. varname .. ', '
    mapping_args = mapping_args .. '@' .. varname .. ', '

    attrs = attrs .. ident .. varname .. ' = [[ CLIENT.mapping.args[' .. j .. '] or @' .. varname .. ' ]];\n'
  end

  params = params:sub (1, -3)
  
  if mapping_args == '' then
    mapping_args = '{}'
  else
    mapping_args = mapping_args:sub (1, -3)
  end

  body = body .. ident .. '[[ apply_mapping ("' .. input.evt ..'", ' .. mapping_args .. ') ]]\n'
  body = body .. attrs

  body = body .. '\t\t\t' .. 'await ' .. input.emitter .. '(' .. params .. ');\n'

  code = code .. body
  if (i == #input_evts) then
    code = code .. '\t\tend'
  end
end

code = code

INPUT_TO_GEN = INPUT_TO_GEN .. CODE_TEMPLATE:gsub('{#1}', code) .. '\n'

maestro_src = maestro_src:gsub ('__COMPILED_EVTS__', INPUT_TO_GEN)
maestro_src = maestro_src:gsub ('__CALLBACK_OUTPUT_COND__', IF_TO_GEN)
maestro_src = maestro_src:gsub ('__OUTPUT_TYPES__', OUTPUT_TO_GEN)
maestro_src = maestro_src:gsub ('__OUTPUT_HANDLE__', OUTPUT_HANDLE_TO_GEN)

f = io.open (arg[1], 'w')
  f:write (maestro_src)
f:close()
