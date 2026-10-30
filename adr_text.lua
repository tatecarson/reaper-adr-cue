-- Small UTF-8 text editor shared by the scene window and its tests.
local M={}
function M.previous(text,pos)
  if pos<=0 then return 0 end
  return (utf8.offset(text,-1,pos+1) or 1)-1
end
function M.following(text,pos)
  if pos>=#text then return #text end
  return (utf8.offset(text,2,pos+1) or (#text+1))-1
end
function M.normalize(text)
  return text:gsub('^\239\187\191',''):gsub('\r\n','\n'):gsub('\r','\n'):gsub('\t','    ')
end
function M.set(state,value)
  state.text=M.normalize(value);state.caret=#state.text;state.anchor=state.caret
  state.scroll=0;state.history={};state.future={}
end
local function snapshot(state)
  return {text=state.text,caret=state.caret,anchor=state.anchor}
end
function M.insert(state,value)
  value=M.normalize(value)
  local a,b=math.min(state.caret,state.anchor),math.max(state.caret,state.anchor)
  if a==b and value=='' then return end
  state.history=state.history or {};state.history[#state.history+1]=snapshot(state)
  if #state.history>100 then table.remove(state.history,1) end
  state.future={}
  state.text=state.text:sub(1,a)..value..state.text:sub(b+1)
  state.caret=a+#value;state.anchor=state.caret
end
function M.undo(state,redo)
  local source=redo and state.future or state.history
  if not source or #source==0 then return end
  local target=redo and state.history or state.future
  target=target or {}
  if redo then state.history=target else state.future=target end
  target[#target+1]=snapshot(state)
  local old=table.remove(source)
  state.text,state.caret,state.anchor=old.text,old.caret,old.anchor
end
function M.move(state,pos,extend)
  state.caret=math.max(0,math.min(#state.text,pos))
  if not extend then state.anchor=state.caret end
end
function M.erase(state,backward)
  local before=snapshot(state)
  local count=#(state.history or {})
  if state.caret==state.anchor then
    state.anchor=backward and M.previous(state.text,state.caret) or M.following(state.text,state.caret)
  end
  M.insert(state,'')
  if #(state.history or {})>count then state.history[#state.history]=before end
end
-- Rows retain byte offsets so soft wrapping never inserts actual line breaks.
function M.rows(text,columns)
  columns=math.max(1,columns)
  local rows,start={},0
  while true do
    local nl=text:find('\n',start+1,true)
    local finish=nl and nl-1 or #text
    local position=start
    repeat
      local stops={position};local nextpos=position
      for _=1,columns do
        if nextpos>=finish then break end
        nextpos=M.following(text,nextpos);stops[#stops+1]=nextpos
      end
      if nextpos<finish then
        -- Prefer a word boundary, while allowing a long word to wrap.
        for i=#stops,math.max(2,math.floor(#stops/2)),-1 do
          if text:sub(stops[i],stops[i]):match('%s') then nextpos=stops[i];break end
        end
      end
      rows[#rows+1]={start=position,finish=nextpos,text=text:sub(position+1,nextpos)}
      position=nextpos
    until position>=finish
    if not nl then break end
    start=nl
  end
  return rows
end
function M.row_at(rows,pos)
  for i,row in ipairs(rows) do
    if pos<row.finish or (pos==row.finish and (not rows[i+1] or rows[i+1].start~=pos)) then return i end
  end
  return #rows
end
function M.column(text,row,pos)
  return utf8.len(text:sub(row.start+1,math.min(pos,row.finish))) or 0
end
function M.at_column(text,row,column)
  local pos=row.start
  for _=1,column do
    if pos>=row.finish then break end
    pos=M.following(text,pos)
  end
  return pos
end
return M
