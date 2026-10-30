-- Pure timing helpers, shared by the application and tests.
local M = {}
function M.split(text)
  local out = {}
  for phrase in (text .. '|'):gmatch('(.-)|') do
    phrase = phrase:match('^%s*(.-)%s*$')
    if phrase ~= '' then out[#out+1] = phrase end
  end
  return out
end
function M.layout(text, start, finish)
  local phrases = M.split(text)
  if #phrases == 0 then return nil, 'Enter at least one phrase.' end
  if start < 4 then return nil, 'Place the line at least four seconds into the project for the count-in.' end
  if finish <= start then return nil, 'Select the duration of the line on the timeline.' end
  local out, step = {}, (finish-start)/#phrases
  for i, phrase in ipairs(phrases) do
    out[i] = {text=phrase, start=start+(i-1)*step, duration=step}
  end
  return out
end
function M.phase(t, start, finish)
  if t < start-3 then return 'READY' end
  if t < start then return tostring(math.ceil(start-t)) end
  if t < finish then return 'SPEAK' end
  return 'TAIL'
end
function M.x(t, phrase_start, anchor, speed)
  return anchor + (phrase_start-t)*speed
end
-- Speaker labels are metadata, never words for the performer to read.
function M.parse_scene(script)
  local turns, current = {}, nil
  script = (script or ''):gsub('^\239\187\191',''):gsub('\r\n','\n'):gsub('\r','\n')
  for line in (script..'\n'):gmatch('(.-)\n') do
    line = line:match('^%s*(.-)%s*$'):gsub('%*%*',''):gsub('__','')
    if line~='' then
      local speaker, dialogue = line:match('^([^:]+):%s*(.*)$')
      if speaker and #speaker<=60 then
        current={speaker=speaker:match('^%s*(.-)%s*$'),text=dialogue}
        turns[#turns+1]=current
      elseif current then
        current.text=current.text..' '..line
      else
        current={speaker='',text=line};turns[#turns+1]=current
      end
    end
  end
  for _,turn in ipairs(turns) do
    turn.text=turn.text:match('^%s*(.-)%s*$')
    if #M.split(turn.text)==0 then return nil,'Each speaker turn needs dialogue.' end
  end
  if #turns==0 then return nil,'Paste a scene with Speaker: dialogue on each turn.' end
  return turns
end
function M.scene_layout(script,start,finish)
  local turns,err=M.parse_scene(script)
  if not turns then return nil,err end
  if not start or not finish or start<4 or finish<=start then
    return nil,'Select the scene range starting at least four seconds into the project.'
  end
  local total=0
  for _,turn in ipairs(turns) do
    local words=0;for _ in turn.text:gmatch('%S+') do words=words+1 end
    turn.weight=math.max(1,words);total=total+turn.weight
  end
  local position=start
  for i,turn in ipairs(turns) do
    turn.start=position
    turn.finish=i==#turns and finish or position+(finish-start)*turn.weight/total
    turn.phrases=assert(M.layout(turn.text,turn.start,turn.finish))
    position=turn.finish;turn.weight=nil
  end
  return turns
end

return M
