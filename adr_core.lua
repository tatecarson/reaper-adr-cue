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
return M
