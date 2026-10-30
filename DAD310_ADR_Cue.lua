-- DAD 310 ADR Cue 0.4.1. Load this file through Actions > New action > Load ReaScript.
-- No SWS, ReaImGui, web server, or compiled plugin required.
local r = reaper
if r.set_action_options then r.set_action_options(1) end
local dir = debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local core = dofile(dir .. 'adr_core.lua')
local editor = dofile(dir .. 'adr_text.lua')
local proj = r.EnumProjects(-1, '')
local NS = 'DAD310_ADR_CUE_V1'
local run, previous_mouse, message = nil, 0, 'Select a range, then Add cue or Paste scene.'
local phrases, scan_at = {}, 0
local function get(key)
  local _, value = r.GetProjExtState(proj, NS, key)
  return value
end
local function put(key,value) r.SetProjExtState(proj,NS,key,tostring(value)) end
local function track(key)
  local guid = get(key)
  for i=0,r.CountTracks(proj)-1 do
    local tr=r.GetTrack(proj,i)
    if r.GetTrackGUID(tr)==guid then return tr end
  end
end
local function ensure(key,name)
  local tr=track(key)
  if not tr then
    r.InsertTrackAtIndex(r.CountTracks(proj),true)
    tr=r.GetTrack(proj,r.CountTracks(proj)-1)
    r.GetSetMediaTrackInfo_String(tr,'P_NAME',name,true)
    put(key,r.GetTrackGUID(tr))
  end
  return tr
end
local function valid(tr) return tr and r.ValidatePtr2(proj,tr,'MediaTrack*') end
local function notice(s) message=s end
local function bounds() return tonumber(get('start')),tonumber(get('finish')) end
local function stopped()
  if get('edit_mode')=='1' then notice('Click Return to ADR to reveal the cue tracks first.'); return false end
  if r.GetPlayStateEx(proj)~=0 then notice('Stop playback before editing the cue.'); return false end
  return true
end
local function cues()
  local list={}
  for id in get('cue_ids'):gmatch('%d+') do
    local prefix='cue_'..id..'_'
    local a,b=tonumber(get(prefix..'start')),tonumber(get(prefix..'finish'))
    if a and b and b>a then list[#list+1]={id=id,start=a,finish=b,speaker=get(prefix..'speaker'),text=get(prefix..'text')} end
  end
  table.sort(list,function(a,b) return a.start==b.start and tonumber(a.id)<tonumber(b.id) or a.start<b.start end)
  return list
end
local function refresh()
  phrases={}
  local tr=track('phrases')
  if tr then
    for i=0,r.CountTrackMediaItems(tr)-1 do
      local item=r.GetTrackMediaItem(tr,i)
      local _,text=r.GetSetMediaItemInfo_String(item,'P_NOTES','',false)
      local _,id=r.GetSetMediaItemInfo_String(item,'P_EXT:DAD310_ADR_CUE_ID','',false)
      if get('active_cue')=='' or id==get('active_cue') then
        phrases[#phrases+1]={item=item,text=text,start=r.GetMediaItemInfo_Value(item,'D_POSITION'),duration=r.GetMediaItemInfo_Value(item,'D_LENGTH')}
      end
    end
    table.sort(phrases,function(a,b) return a.start<b.start end)
  end
end
local function restore()
  if not run then return end
  if valid(run.guide) then r.SetMediaTrackInfo_Value(run.guide,'D_VOL',run.volume) end
  if valid(run.beeps) then r.SetMediaTrackInfo_Value(run.beeps,'B_MUTE',1) end
  for _,entry in ipairs(run.items or {}) do
    if r.ValidatePtr2(proj,entry.item,'MediaItem*') then
      r.SetMediaItemInfo_Value(entry.item,'B_MUTE',entry.mute)
      r.GetSetMediaItemInfo_String(entry.item,'P_EXT:DAD310_ADR_MUTE','',true)
    end
  end
  r.GetSetRepeatEx(proj,run.repeat_state)
  run=nil
  put('needs_restore','0')
end
local function stop()
  if run then r.OnStopButtonEx(proj); restore() end
end
local function undo(label,fn)
  r.Undo_BeginBlock2(proj)
  local ok,err=xpcall(fn,debug.traceback)
  r.Undo_EndBlock2(proj,label,-1)
  r.UpdateArrange()
  if not ok then error(err) end
end
-- Edit mode persists in the project, even after closing this window.
local function toggle_edit_mode()
  if r.GetPlayStateEx(proj)~=0 then notice('Stop playback before switching between editing and ADR.'); return end
  if run then restore() end
  local editing=get('edit_mode')=='1'
  if not editing then
    local guide=track('guide')
    if not guide or not track('phrases') then notice('Create a line and assign its guide before entering Edit mode.'); return end

  end
  undo(editing and 'Return to ADR tracks' or 'Hide ADR support tracks for editing',function()
    if editing then
      for i=1,tonumber(get('edit_count')) or 0 do
        local prefix='edit_'..i..'_'
        for j=0,r.CountTracks(proj)-1 do
          local tr=r.GetTrack(proj,j)
          if r.GetTrackGUID(tr)==get(prefix..'guid') then
            for _,field in ipairs({'B_SHOWINTCP','B_SHOWINMIXER','D_VOL','B_MUTE'}) do
              local value=tonumber(get(prefix..field))
              if value then r.SetMediaTrackInfo_Value(tr,field,value) end
            end
            break
          end
        end
      end
      put('edit_mode','0')
    else
      local seen,count={},0
      for _,key in ipairs({'phrases','beeps','guide'}) do
        local tr=track(key)
        if tr and not seen[r.GetTrackGUID(tr)] then
          local guid=r.GetTrackGUID(tr);seen[guid]=true;count=count+1
          local prefix='edit_'..count..'_'
          put(prefix..'guid',guid)
          for _,field in ipairs({'B_SHOWINTCP','B_SHOWINMIXER'}) do
            put(prefix..field,'')
            if key~='guide' then
              put(prefix..field,r.GetMediaTrackInfo_Value(tr,field))
              r.SetMediaTrackInfo_Value(tr,field,0)
            end
          end
          -- Store only properties changed by this mode; leave the video enabled.
          put(prefix..'D_VOL','');put(prefix..'B_MUTE','')
          if key=='beeps' then
            put(prefix..'B_MUTE',r.GetMediaTrackInfo_Value(tr,'B_MUTE'))
            r.SetMediaTrackInfo_Value(tr,'B_MUTE',1)
          end
        end
      end
      put('edit_count',count);put('edit_mode','1')
    end
    r.TrackList_AdjustWindows(false)
  end)
  notice(editing and 'ADR tracks restored. Rehearse or record when ready.' or 'Edit mode: support tracks hidden and location audio unchanged. Edit your takes in REAPER. Return to ADR restores the previous track settings.')
end
local function make_beeps(start)
  local tr=ensure('beeps','ADR COUNT-IN (muted when idle)')
  for i=r.CountTrackMediaItems(tr)-1,0,-1 do r.DeleteTrackMediaItem(tr,r.GetTrackMediaItem(tr,i)) end
  for i=1,3 do
    local source=r.PCM_Source_CreateFromFile(dir..'adr-beep.wav')
    if not source then error('Missing adr-beep.wav. Extract the complete ZIP before loading the script.') end
    local item=r.AddMediaItemToTrack(tr)
    local take=r.AddTakeToMediaItem(item)
    r.SetMediaItemTake_Source(take,source)
    r.SetMediaItemInfo_Value(item,'D_POSITION',start-4+i)
    r.SetMediaItemInfo_Value(item,'D_LENGTH',0.08)
    r.SetMediaItemInfo_Value(item,'C_LOCK',1)
    r.SetMediaItemInfo_Value(item,'C_BEATATTACHMODE',0)
    r.GetSetMediaItemTakeInfo_String(take,'P_NAME','ADR beep '..i,true)
  end
  r.SetMediaTrackInfo_Value(tr,'B_MUTE',1)
end
local function select_cue(id)
  if not stopped() then return end
  local selected
  for _,cue in ipairs(cues()) do if cue.id==id then selected=cue;break end end
  if not selected then notice('Choose an existing cue.');return end
  undo('Select ADR cue',function()
    put('active_cue',id);put('start',selected.start);put('finish',selected.finish);put('text',selected.text)
    make_beeps(selected.start)
    r.GetSet_LoopTimeRange2(proj,true,false,selected.start,selected.finish,false)
    r.SetEditCurPos2(proj,selected.start-4,true,false)
  end)
  refresh()
  notice('Cue selected. Beeps follow its entrance; other cues and recordings stay in place.')
end
local function step_cue(direction)
  if not stopped() then return end
  local list=cues()
  for i,cue in ipairs(list) do
    if cue.id==get('active_cue') then
      local target=list[i+direction]
      if target then select_cue(target.id) else notice(direction<0 and 'First cue in the session.' or 'Last cue in the session.') end
      return
    end
  end
  if list[1] then select_cue(list[1].id) else notice('Add a cue or paste a scene first.') end
end
local function cue_label(cue)
  local words=(cue.speaker~='' and cue.speaker..': ' or '')..cue.text:gsub('|',' / ')
  return string.format('%.2fs  %s',cue.start,words):gsub('[\r\n]',' ')
end
local function choose_cue()
  if not stopped() then return end
  local list=cues();local labels={}
  for _,cue in ipairs(list) do
    labels[#labels+1]=(cue.id==get('active_cue') and '!' or '')..cue_label(cue):sub(1,110):gsub('[|!#<>]',' ')
  end
  if #list==0 then notice('Add a cue or paste a scene first.');return end
  gfx.x=210;gfx.y=70
  local choice=gfx.showmenu(table.concat(labels,'|'))
  if list[choice] then select_cue(list[choice].id) end
end
local function append_cues(turns)
  local ids=get('cue_ids');local first
  undo('Add ADR session cues',function()
    local tr=ensure('phrases','ADR PHRASES - all session cues')
    for _,turn in ipairs(turns) do
      local id=tostring((tonumber(get('cue_sequence')) or 0)+1)
      put('cue_sequence',id);first=first or id
      ids=ids=='' and id or ids..','..id
      for _,field in ipairs({'start','finish','speaker','text'}) do put('cue_'..id..'_'..field,turn[field] or '') end
      for _,p in ipairs(turn.phrases) do
        local item=r.AddMediaItemToTrack(tr)
        r.SetMediaItemInfo_Value(item,'D_POSITION',p.start)
        r.SetMediaItemInfo_Value(item,'D_LENGTH',p.duration)
        r.SetMediaItemInfo_Value(item,'C_BEATATTACHMODE',0)
        r.GetSetMediaItemInfo_String(item,'P_NOTES',p.text,true)
        r.GetSetMediaItemInfo_String(item,'P_EXT:DAD310_ADR_CUE_ID',id,true)
      end
    end
    put('cue_ids',ids)
    local existing=track('record');local rec=ensure('record','ADR RECORD - choose microphone input')
    if not existing then
      r.SetMediaTrackInfo_Value(rec,'I_RECARM',0);r.SetMediaTrackInfo_Value(rec,'I_RECMODE',0)
      r.SetMediaTrackInfo_Value(rec,'I_RECINPUT',-1);r.SetMediaTrackInfo_Value(rec,'I_RECMON',0)
    end
    local first_turn=turns[1]
    put('active_cue',first);put('start',first_turn.start);put('finish',first_turn.finish);put('text',first_turn.text)
    make_beeps(first_turn.start)
  end)
  refresh()
end
local function new_line()
  if not stopped() then return end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  local ok,input=r.GetUserInputs('Add cue: optional Speaker: and | between phrases',1,'Dialogue,extrawidth=700','')
  if not ok then return end
  local turns,err=core.scene_layout(input,a,b)
  if not turns then notice(err);return end
  append_cues(turns)
  notice('Cue added. Existing cues remain. Align its phrase items and use the cue list to switch lines.')
end
-- Clipboard text is only read after an explicit Paste text click. No script text is executed.
local function clipboard_text()
  if r.CF_GetClipboard then return r.CF_GetClipboard() end
  if not r.ExecProcess or not r.GetOS then return nil end
  local osname=r.GetOS();local command
  if osname:find('OSX') or osname:find('macOS') then command='/usr/bin/pbpaste'
  elseif osname:find('Win') then
    command='powershell.exe -NoProfile -NonInteractive -Command "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); Get-Clipboard -Raw"'
  end
  if not command then return nil end
  local output=r.ExecProcess(command,3000)
  if not output then return nil end
  local code,value=output:match('^([^\n]+)\n(.*)$')
  if tonumber(code)==0 then return value end
end
local scene_input=nil
local function open_scene()
  if not stopped() then return end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  if a<4 or b<=a then notice('Select the whole scene range, at least four seconds into the project.');return end
  scene_input={start=a,finish=b,message='Paste or load a scene, then click in the text to edit it and add | breaks.'}
  editor.set(scene_input,'')
end
local function set_guide()
  if not stopped() then return end
  local tr=r.GetSelectedTrack(proj,0)
  if not tr or tr==track('phrases') or tr==track('record') or tr==track('beeps') then notice('Select the track with the original dialogue audio.'); return end
  if r.GetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH')~=0 or r.GetTrackNumSends(tr,0)>0 or r.GetTrackNumSends(tr,1)>0 then
    notice('Use a plain guide track without sends or hardware outputs.'); return
  end
  if r.GetTrackEnvelopeByName(tr,'Volume') then notice('Remove volume automation from the guide track first.'); return end
  put('guide',r.GetTrackGUID(tr))
  notice('Guide assigned. Rehearse plays it; Perform and Record silence it at the entrance.')
end
local function start(mode)
  if run then stop(); return end
  if not stopped() then return end
  local a,b=bounds()
  if not a then notice('Create a line first.'); return end
  if r.Master_GetPlayRate(proj)~=1 then notice('Set project playback rate to 1.0 for this cue.'); return end
  local guide=track('guide')
  if not guide then notice('Select the original dialogue track and click Set guide.'); return end
  if r.GetMediaTrackInfo_Value(guide,'B_MUTE')~=0 then notice('Unmute the guide before starting.'); return end
  if r.GetTrackEnvelopeByName(guide,'Volume') or r.GetTrackNumSends(guide,0)>0 or r.GetTrackNumSends(guide,1)>0 then notice('Guide must have no volume automation or sends.'); return end
  if r.AnyTrackSolo(proj) then notice('Clear track solos so the picture, guide and count-in can play.'); return end
  local beeps=track('beeps')
  if not beeps then notice('Recreate the line to restore its count-in.'); return end
  if mode=='Record' then
    local _,filename=r.EnumProjects(-1,'')
    if not filename or filename=='' then notice('Save this project before recording.'); return end
    local rec=track('record')
    if not rec or r.GetMediaTrackInfo_Value(rec,'I_RECARM')~=1 or r.GetMediaTrackInfo_Value(rec,'I_RECINPUT')<0 then
      notice('Choose a microphone input and arm only ADR RECORD before recording.'); return
    end
    if r.GetMediaTrackInfo_Value(rec,'I_RECMODE')~=0 then notice('Set ADR RECORD to record input audio.'); return end
    for i=0,r.CountTracks(proj)-1 do
      local tr=r.GetTrack(proj,i)
      if tr~=rec and r.GetMediaTrackInfo_Value(tr,'I_RECARM')~=0 then notice('Disarm other tracks first.'); return end
    end
    if r.GetToggleCommandStateEx(0,40252)~=1 then notice('Choose Options > Record mode: normal first.'); return end
  end
  run={mode=mode,guide=guide,volume=r.GetMediaTrackInfo_Value(guide,'D_VOL'),beeps=beeps,repeat_state=r.GetSetRepeatEx(proj,-1),finish=b+1,start=a}
  run.items={}
  local rec=track('record')
  if rec then
    for i=0,r.CountTrackMediaItems(rec)-1 do
      local item=r.GetTrackMediaItem(rec,i)
      run.items[#run.items+1]={item=item,mute=r.GetMediaItemInfo_Value(item,'B_MUTE')}
      r.GetSetMediaItemInfo_String(item,'P_EXT:DAD310_ADR_MUTE',tostring(run.items[#run.items].mute),true)
      r.SetMediaItemInfo_Value(item,'B_MUTE',1)
    end
  end
  -- Persist restoration data in case REAPER or the script terminates unexpectedly.
  put('restore_volume',run.volume); put('restore_repeat',run.repeat_state); put('needs_restore','1')
  r.GetSetRepeatEx(proj,0)
  r.SetMediaTrackInfo_Value(beeps,'B_MUTE',0)
  r.SetEditCurPos2(proj,a-4,true,false)
  if mode=='Record' then r.CSurf_OnRecord() else r.OnPlayButtonEx(proj) end
  notice(mode..': press Stop to finish early. One second of tail follows the line.')
end
local function edit_phrase()
  if not stopped() then return end
  local item=r.GetSelectedMediaItem(proj,0)
  if not item or r.GetMediaItemTrack(item)~=track('phrases') then notice('Select a phrase item on ADR PHRASES first.'); return end
  local _,id=r.GetSetMediaItemInfo_String(item,'P_EXT:DAD310_ADR_CUE_ID','',false)
  if get('active_cue')~='' and id~=get('active_cue') then notice('Choose this item’s cue in the cue list first.');return end
  local _,old=r.GetSetMediaItemInfo_String(item,'P_NOTES','',false)
  local ok,text=r.GetUserInputs('Edit phrase',1,'Text,extrawidth=700',old)
  if ok and text:match('%S') then undo('Edit ADR phrase',function() r.GetSetMediaItemInfo_String(item,'P_NOTES',text,true) end); refresh() end
end
local function update_bounds()
  if not stopped() then return end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  if a<4 or b<=a then notice('Select a line range starting at least four seconds into the project.'); return end
  if not track('phrases') then notice('Create a line first.'); return end
  undo('Update ADR cue range',function()
    put('start',a);put('finish',b)
    local id=get('active_cue')
    if id~='' then put('cue_'..id..'_start',a);put('cue_'..id..'_finish',b) end
    make_beeps(a)
  end)
  notice('Cue range updated. Phrase positions stay where you placed them.')
end
local help_open,help_page=false,1
local hover_id,hover_since=nil,0
local hover_x,hover_y=nil,nil
local tips={
  ['Add cue']='Add a cue without replacing existing lines.',
  ['Paste scene']='Paste or load a whole scene. One cue per speaker turn.',
  ['Previous']='Select the previous cue and move the beeps.',
  ['Next']='Select the next cue and move the beeps.',
  ['Cue list']='Choose any saved cue in the session.',
  ['Set guide']='Use the selected track as the original dialogue.',
  ['Edit phrase']="Change the selected phrase item's text.",
  ['Use range']='Update cue timing from the time selection.',
  ['Rehearse']='Practice with the original. Does not record.',
  ['Perform']='Practice without the original. Does not record.',
  ['Record']='Record onto the armed ADR RECORD track.',
  ['Stop']='Stop and restore guide and take levels.',
  ['Edit in REAPER']='Hide cue tracks; keep picture and location audio.',
  ['Return to ADR']='Restore the cue tracks for rehearsal or recording.',
  ['Help']='Setup, recording, and troubleshooting.'
}
local help_pages={
  {title='1 / Set up and sync',body={
    'Save the project. Import your video and place it at 10 seconds to leave room for the count-in.',
    'Drag a time selection in the ruler over the spoken line. Selecting the video item alone is not enough.',
    'Add cue appends one line. Paste scene accepts Speaker: dialogue turns, including Markdown bold labels. Review the preview before Add cues.',
    'Select the original dialogue track and click Set guide. Clear all track solos.',
    'Initial cue timing is approximate. Align phrase items to speech, select each line’s time range, then Use range. Previous/Next or the cue list loads that line and moves the beeps.',
    'Speak when the phrase reaches the FIXED GREEN LINE. The amber strip above the words is only the count-in. Use shorter phrases for finer timing.'}},
  {title='2 / Rehearse, record, review',body={
    'Rehearse: hear the original and practice its rhythm. Perform: practice with the guide silenced at the entrance. Neither records.',
    'For Record: save the project, choose your microphone input on ADR RECORD, arm that track, and disarm all other tracks. Use normal record mode and headphones.',
    "Click Record HERE, not on REAPER's transport, for automatic guide control. Hear three beeps; speak on the silent fourth beat. Recording stops one second after the line.",
    'Previous ADR RECORD items are silenced during each run and restored afterward. Use Record again for another take. Keep the files if REAPER asks.',
    "Click Edit in REAPER to hide cue tracks. Picture and location audio stay unchanged. Replace only the original line on a working copy; comp in fixed item lanes.",
    'Space toggles rehearsal/stop in the cue window. In Help, Space only stops an active run. Escape closes Help; a second Escape closes the tool.'}},
  {title='3 / If something does not work',body={
    'Nothing starts? Read the status message below the cues. Clear solos, unmute the guide, and set project playback rate to 1.0.',
    'Four-second warning? The time selection must start at least four seconds into the project. Move the video later and select the spoken line again.',
    'Words out of sync? Move phrase items to match the original. Only phrase beginnings are timed; words within each phrase are not aligned individually.',
    "Original audible while recording? Use this window's Record button and assign the correct guide. Check for another copy playing on a different track.",
    'No microphone? Choose an input and arm ADR RECORD. Enable input monitoring only if needed. Guide tracks must have no volume automation or sends.',
    'Cue lists and phrase items save with the project. Switching lines preserves other cues and takes. Stop playback before switching. Keep ADR COUNT-IN muted when mixing.'}}
}
local buttons={
  {'Add cue',new_line},{'Set guide',set_guide},{'Edit phrase',edit_phrase},{'Use range',update_bounds},
  {'Rehearse',function() start('Rehearse') end},{'Perform',function() start('Perform') end},
  {'Record',function() start('Record') end},{'Stop',stop}
}
local function color(a,b,c) gfx.set(a,b,c,1) end
local function text(x,y,s,size)
  gfx.setfont(1,'Arial',size or 16);gfx.x=x;gfx.y=y;gfx.drawstr(s)
end
local function wrapped(value,x,y,width,size)
  gfx.setfont(1,'Arial',size)
  local line=''
  for word in value:gmatch('%S+') do
    if line~='' and gfx.measurestr(line..word)>width then
      text(x,y,line,size);y=y+size+5;line=''
    end
    line=line..word..' '
  end
  text(x,y,line,size)
  return y+size+5
end
local function inside(x,y,w,h)
  return gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+h
end
local function draw_help(mouse,pressed)
  color(.07,.09,.10);gfx.rect(0,0,gfx.w,gfx.h,true)
  color(.93,.91,.85);text(20,16,'ADR CUE / HELP',23)
  local labels={'Setup','Recording','Troubleshooting','Close help'}
  for i,label in ipairs(labels) do
    local bw=(gfx.w-46)/4;local x=20+(i-1)*(bw+2)
    local hover=inside(x,55,bw,32)
    color(hover and .27 or .16,.24,.24);gfx.rect(x,55,bw,32,true)
    color(.94,.92,.86);text(x+10,63,label,15)
    if hover and pressed then
      if i==4 then help_open=false else help_page=i end
    end
  end
  local page=help_pages[help_page]
  color(.35,.85,.69);text(20,103,page.title,21)
  local y=140
  color(.87,.89,.87)
  for _,paragraph in ipairs(page.body) do y=wrapped(paragraph,20,y,gfx.w-40,15)+10 end
end
local function draw_scene(pressed)
  color(.07,.09,.10);gfx.rect(0,0,gfx.w,gfx.h,true)
  color(.93,.91,.85);text(20,16,'PASTE A SCENE',23)
  color(.69,.77,.82);text(20,49,'Speaker: dialogue, one turn per line. Existing cues stay in place.',15)
  local actions={
    {'Paste text',function()
      local value=clipboard_text()
      if value and value:match('%S') then editor.set(scene_input,value);scene_input.reveal=true;scene_input.message='Click in the text to edit. Add | for phrase breaks, then Add cues.'
      else scene_input.message='Clipboard unavailable or empty. Save the script as UTF-8 .txt and use Load .txt.' end
    end},
    {'Load .txt',function()
      local ok,path=r.GetUserFileNameForRead('','Load scene script','.txt')
      if ok then
        local file=io.open(path,'rb')
        if file then editor.set(scene_input,file:read('*a'));scene_input.reveal=true;file:close();scene_input.message='Edit the script and add | breaks, then Add cues.'
        else scene_input.message='Could not read that text file.' end
      end
    end},
    {'Add cues',function()
      if not stopped() then return end
      local turns,err=core.scene_layout(scene_input.text,scene_input.start,scene_input.finish)
      if not turns then scene_input.message=err;return end
      append_cues(turns);scene_input=nil
      notice(#turns..' cues added. Timing is approximate: align phrases, select each cue’s range, then Use range before recording.')
    end},
    {'Cancel',function() scene_input=nil end}
  }
  for i,button in ipairs(actions) do
    local bw=(gfx.w-55)/4;local x=20+(i-1)*(bw+5);local hover=inside(x,78,bw,32)
    color(hover and .27 or .17,.25,.27);gfx.rect(x,78,bw,32,true)
    color(.94,.94,.90);text(x+10,86,button[1],15)
    if hover and pressed then button[2]();return end
  end
  color(.94,.77,.48);wrapped(scene_input.message,20,126,gfx.w-40,15)
  local turns=core.parse_scene(scene_input.text)
  color(.68,.78,.81)
  text(20,174,(turns and #turns..' cues' or 'No cues yet')..' / click to edit / | separates phrases / Enter starts a speaker turn',14)
  local x,y,bw,bh=20,202,gfx.w-40,gfx.h-248
  color(.035,.05,.06);gfx.rect(x,y,bw,bh,true)
  gfx.setfont(1,'Courier New',17)
  local cw=gfx.measurestr('M');cw=math.max(1,cw);local lineheight=25
  local rows=editor.rows(scene_input.text,math.floor((bw-24)/cw))
  local visible=math.max(1,math.floor((bh-16)/lineheight))
  local wheel=gfx.mouse_wheel or 0
  if wheel~=0 and inside(x,y,bw,bh) then
    scene_input.scroll=math.max(0,math.min(math.max(0,#rows-visible),scene_input.scroll-math.floor(wheel/120)*3))
    gfx.mouse_wheel=0
  end
  if pressed and inside(x,y,bw,bh) then
    scene_input.dragging=true
    local row=rows[math.min(#rows,math.max(1,math.floor((gfx.mouse_y-y-8)/lineheight)+1+scene_input.scroll))]
    local column=math.max(0,math.floor((gfx.mouse_x-x-12)/cw+.5))
    editor.move(scene_input,editor.at_column(scene_input.text,row,column),(gfx.mouse_cap&8)~=0)
  elseif scene_input.dragging and (gfx.mouse_cap&1)~=0 then
    local index=math.min(#rows,math.max(1,math.floor((gfx.mouse_y-y-8)/lineheight)+1+scene_input.scroll))
    local column=math.max(0,math.floor((gfx.mouse_x-x-12)/cw+.5))
    editor.move(scene_input,editor.at_column(scene_input.text,rows[index],column),true)
  elseif (gfx.mouse_cap&1)==0 then scene_input.dragging=false end
  if scene_input.reveal then
    local row=editor.row_at(rows,scene_input.caret)
    scene_input.scroll=math.max(0,math.min(scene_input.scroll,row-1))
    if row>scene_input.scroll+visible then scene_input.scroll=row-visible end
    scene_input.reveal=false
  end
  scene_input.rows=rows
  scene_input.scroll=math.min(scene_input.scroll,math.max(0,#rows-visible))
  local sa,sb=math.min(scene_input.caret,scene_input.anchor),math.max(scene_input.caret,scene_input.anchor)
  for i=scene_input.scroll+1,math.min(#rows,scene_input.scroll+visible) do
    local row=rows[i];local py=y+8+(i-scene_input.scroll-1)*lineheight
    if sa<row.finish and sb>row.start then
      local left=editor.column(scene_input.text,row,math.max(sa,row.start))
      local right=editor.column(scene_input.text,row,math.min(sb,row.finish))
      color(.16,.32,.39);gfx.rect(x+12+left*cw,py,math.max(cw,(right-left)*cw),lineheight,true)
    end
    color(.90,.92,.90);gfx.setfont(1,'Courier New',17);gfx.x=x+12;gfx.y=py;gfx.drawstr(row.text)
    if editor.row_at(rows,scene_input.caret)==i then
      local column=editor.column(scene_input.text,row,scene_input.caret)
      color(.44,.91,.73);gfx.rect(x+12+column*cw,py,2,21,true)
    end
  end
  color(.68,.75,.78);text(20,gfx.h-32,'Arrows move the cursor. Shift selects. Ctrl/Cmd+A selects all; Ctrl/Cmd+V pastes; Ctrl/Cmd+Z undoes.',13)

end
local function scene_key(key,unicode)
  local input=scene_input
  local shift=(gfx.mouse_cap&8)~=0
  local command=(gfx.mouse_cap&(4|32))~=0
  local letter=key>=65 and key<=90 and key+32 or key
  if key==1 or (command and letter==97) then input.anchor=0;input.caret=#input.text
  elseif key==22 or (command and letter==118) then
    local value=clipboard_text()
    if value then editor.insert(input,value) end
  elseif key==26 or (command and letter==122) then editor.undo(input,shift)
  elseif key==8 then editor.erase(input,true)
  elseif key==6579564 or key==127 then editor.erase(input,false)
  elseif key==13 or key==10 then editor.insert(input,'\n')
  elseif key==1818584692 or key==1919379572 then
    local left=key==1818584692
    local pos
    if not shift and input.caret~=input.anchor then pos=left and math.min(input.caret,input.anchor) or math.max(input.caret,input.anchor)
    else pos=left and editor.previous(input.text,input.caret) or editor.following(input.text,input.caret) end
    editor.move(input,pos,shift)
  elseif key==30064 or key==1685026670 or key==1752132965 or key==6647396 then
    local rows=input.rows or editor.rows(input.text,80)
    local index=editor.row_at(rows,input.caret)
    if key==1752132965 then editor.move(input,command and 0 or rows[index].start,shift)
    elseif key==6647396 then editor.move(input,command and #input.text or rows[index].finish,shift)
    else
      local target=math.max(1,math.min(#rows,index+(key==30064 and -1 or 1)))
      editor.move(input,editor.at_column(input.text,rows[target],editor.column(input.text,rows[index],input.caret)),shift)
    end
  elseif not command then
    local code=unicode and unicode>0 and unicode or key
    if code>=32 and code<=0x10ffff and key<0x1000000 then
      editor.insert(input,utf8.char(code))
    end
  end
  input.reveal=true
end
local function frame()
  if r.ValidatePtr and not r.ValidatePtr(proj,'ReaProject*') then run=nil;gfx.quit();return end
  if r.EnumProjects(-1,'')~=proj then stop(); gfx.quit(); return end
  local state=r.GetPlayStateEx(proj)
  local t=state~=0 and r.GetPlayPositionEx(proj) or r.GetCursorPositionEx(proj)
  local a,b=bounds()
  if run then
    if state==0 then restore(); put('needs_restore','0')
    elseif t>=run.finish then stop(); put('needs_restore','0')
    elseif valid(run.guide) then
      local volume=run.mode~='Rehearse' and t>=run.start and 0 or run.volume
      r.SetMediaTrackInfo_Value(run.guide,'D_VOL',volume)
    else stop(); notice('Guide removed. Session stopped.') end
  end
  if r.time_precise()>scan_at then refresh();scan_at=r.time_precise()+0.15 end
  gfx.clear=0x191512
  local w=gfx.w
  color(.93,.91,.85);text(20,16,'ADR CUE 0.4.1',24)
  local navigation={{'Paste scene',20,110,open_scene},{'Previous',138,78,function() step_cue(-1) end},{'Cue list',224,w-332,choose_cue},{'Next',w-100,80,function() step_cue(1) end}}
  local current_label='Choose a cue'
  local list=cues()
  for i,cue in ipairs(list) do if cue.id==get('active_cue') then current_label=i..'/'..#list..'  '..cue_label(cue) end end
  local mouse=gfx.mouse_cap&1
  local pressed=mouse==1 and previous_mouse==0
  local hovered=nil
  local blocked=help_open or scene_input~=nil
  local help_hover=inside(w-100,14,80,30)
  color(help_hover and .27 or .17,.23,.24);gfx.rect(w-100,14,80,30,true)
  color(.95,.94,.89);text(w-83,21,'Help ?',15)
  if not blocked and help_hover then
    hovered='Help'
    if pressed then help_open=true end
  end
  local edit_label=get('edit_mode')=='1' and 'Return to ADR' or 'Edit in REAPER'
  local edit_hover=inside(w-280,14,168,30)
  color(.18,edit_hover and .30 or .24,.31);gfx.rect(w-280,14,168,30,true)
  color(.95,.94,.89);text(w-270,21,edit_label,15)
  if not blocked and edit_hover then
    hovered=edit_label
    if pressed then toggle_edit_mode() end
  end
  local sections={
    {name='1  SETUP',indices={1,2}},
    {name='2  EDIT TIMING',indices={3,4}},
    {name='3  REHEARSE',indices={5,6}},
    {name='4  RECORD',indices={7,8}}
  }
  local tip_x,tip_y=edit_hover and w-280 or w-100,48
  for _,button in ipairs(navigation) do
    local label,x,bw,action=table.unpack(button);local hover=inside(x,46,bw,24)
    color(hover and .25 or .16,.22,.25);gfx.rect(x,46,bw,24,true)
    local caption=label=='Cue list' and current_label or label
    gfx.setfont(1,'Arial',13)
    while #caption>3 and gfx.measurestr(caption)>bw-16 do caption=caption:sub(1,-5)..'...' end
    color(.94,.94,.90);text(x+8,51,caption,13)
    if hover and not blocked then hovered=label;tip_x=x;tip_y=74;if pressed then action() end end
  end
  for column,section in ipairs(sections) do
    local panel=(w-70)/4;local x=20+(column-1)*(panel+10)
    color(.10,.12,.15);gfx.rect(x,76,panel,110,true)
    color(.68,.73,.80);text(x+10,85,section.name,12)
    for row,index in ipairs(section.indices) do
      local button=buttons[index];local y=108+(row-1)*38;local bw=panel-20
      local hover=inside(x+10,y,bw,32)
      local active=run and run.mode==button[1]
      if button[1]=='Record' then
        color(active and .75 or (hover and .61 or .48),.16,.20)
      elseif column==3 then
        color(.13,active and .40 or (hover and .30 or .23),active and .59 or .36)
      else
        local shade=hover and .25 or .18;color(shade,shade+.02,shade+.05)
      end
      gfx.rect(x+10,y,bw,32,true)
      color(.96,.97,.98)
      -- Shapes reinforce transport meaning without relying on color.
      local tx=x+20
      if button[1]=='Record' then gfx.circle(x+23,y+16,4,true);tx=x+35
      elseif button[1]=='Stop' then gfx.rect(x+19,y+12,8,8,true);tx=x+35 end
      text(tx,y+7,button[1],16)
      if active then color(.96,.97,.98);gfx.rect(x+10,y+30,bw,2,true) end
      if hover and not blocked then
        hovered=button[1];tip_x=x+10;tip_y=y-48
        if pressed then button[2]() end
      end
    end
  end
  local phase=a and core.phase(t,a,b) or 'SET A LINE'
  local mode=run and run.mode or nil
  if mode=='Record' then color(1,.49,.51)
  elseif run then color(.48,.75,1) else color(.85,.89,.94) end
  local title=mode and (mode=='Record' and 'RECORDING' or mode=='Rehearse' and 'REHEARSING' or 'PERFORMING') or 'READY'
  if get('edit_mode')=='1' then title='EDITING IN REAPER' elseif not a then title='START WITH A LINE' end
  text(20,202,title,24)
  color(.70,.76,.83)
  local detail=run and (phase=='SPEAK' and 'Speak at the green line' or phase=='TAIL' and 'Finishing the take' or 'Count-in: '..phase)
    or 'Select a mode above. Audition and comp takes in REAPER.'
  if get('edit_mode')=='1' then detail='Location audio unchanged / cue tracks hidden / recordings available in REAPER' end
  text(20,235,detail,14)
  local timing=a and string.format('%.2f - %.2fs',a,b) or 'No cue yet'
  gfx.setfont(1,'Arial',14)
  text(w-20-gfx.measurestr(timing),208,timing,14)
  local y=269;local anchor=math.min(200,w*.23);local speed=180
  color(.09,.12,.13);gfx.rect(0,y,w,180,true)
  color(.35,.85,.69);gfx.rect(anchor,y+28,2,152,true)
  text(anchor+8,y+7,'SPEAK HERE',12)
  for i,p in ipairs(phrases) do
    local x=core.x(t,p.start,anchor,speed)
    -- Separate alternating phrases into lanes so long text remains readable.
    local lane=(i-1)%2;local py=y+40+lane*66
    if t>=p.start and t<p.start+p.duration then color(.98,.98,.96) else color(.73,.78,.82) end
    text(x,py,p.text,28)
    color(.26,.48,.43);gfx.rect(x,py+33,math.max(2,p.duration*speed),3,true)
  end
  if state~=0 and a and t>=a-3 and t<a then
    -- Count-in stays above the dialogue so it cannot be mistaken for a reading cursor.
    color(.22,.24,.25);gfx.rect(20,257,w-40,5,true)
    color(.94,.72,.35);gfx.rect(20,257,(t-(a-3))/3*(w-40),5,true)
  end
  color(.60,.68,.69);text(20,465,'Speak as each phrase reaches the fixed green line. Amber strip = count-in only.',14)
  -- Wrap status text to avoid hiding setup instructions in smaller windows.
  gfx.setfont(1,'Arial',15)
  local line,yy='',497
  color(.81,.86,.91)
  for word in message:gmatch('%S+') do
    if gfx.measurestr(line..word)>w-45 then text(20,yy,line,15);yy=yy+20;line='' end
    line=line..word..' '
  end
  text(20,yy,line,15)
  local moved=hover_x~=gfx.mouse_x or hover_y~=gfx.mouse_y
  if scene_input then
    draw_scene(pressed)
    hovered=nil
  elseif help_open then
    draw_help(mouse,pressed)
    hovered=nil
  end
  -- Wait for a still pointer; never show hints while any transport is active.
  if not hovered or hovered~=hover_id or moved or mouse~=0 or run or state~=0 then
    hover_since=r.time_precise()
  elseif not help_open and r.time_precise()-hover_since>=1.2 then
    local tw=math.min(360,w-40)
    local tx=math.max(20,math.min(tip_x,w-tw-20))
    local ty=math.max(48,tip_y)
    color(.20,.23,.26);gfx.rect(tx,ty,tw,44,true)
    color(.98,.92,.76);wrapped(tips[hovered],tx+10,ty+5,tw-20,14)
  end
  hover_id=hovered;hover_x=gfx.mouse_x;hover_y=gfx.mouse_y
  previous_mouse=mouse
  gfx.update()
  local key,unicode=gfx.getchar()
  if key<0 then stop();gfx.quit();return end
  if key==27 then
    if scene_input then scene_input=nil elseif help_open then help_open=false else stop();gfx.quit();return end
  end
  if scene_input and key>0 and key~=27 then scene_key(key,unicode) end
  if key==63 and not scene_input then help_open=not help_open end
  if key==32 then if run then stop() elseif not help_open and not scene_input then start('Rehearse') end end
  r.defer(function()
    local ok,err=xpcall(frame,debug.traceback)
    if not ok then stop();gfx.quit();r.MB(err,'ADR Cue stopped',0) end
  end)
end
-- Recover temporary routing state after an interrupted previous run.
if get('needs_restore')=='1' then
  local guide=track('guide');local volume=tonumber(get('restore_volume'))
  if guide and volume then r.SetMediaTrackInfo_Value(guide,'D_VOL',volume) end
  local beeps=track('beeps');if beeps then r.SetMediaTrackInfo_Value(beeps,'B_MUTE',1) end
  r.GetSetRepeatEx(proj,tonumber(get('restore_repeat')) or 0)
  local rec=track('record')
  if rec then
    for i=0,r.CountTrackMediaItems(rec)-1 do
      local item=r.GetTrackMediaItem(rec,i)
      local _,value=r.GetSetMediaItemInfo_String(item,'P_EXT:DAD310_ADR_MUTE','',false)
      if tonumber(value) then
        r.SetMediaItemInfo_Value(item,'B_MUTE',tonumber(value))
        r.GetSetMediaItemInfo_String(item,'P_EXT:DAD310_ADR_MUTE','',true)
      end
    end
  end
  put('needs_restore','0')
end
-- v0.3.0 hid the guide as well. Restore only its saved visibility,
-- keeping Edit mode active and restoring the location audio.
if get('edit_mode')=='1' then
  local guide=track('guide')
  if guide then
    local changed=false
    for i=1,tonumber(get('edit_count')) or 0 do
      local prefix='edit_'..i..'_'
      if get(prefix..'guid')==r.GetTrackGUID(guide) then
        for _,field in ipairs({'B_SHOWINTCP','B_SHOWINMIXER','D_VOL'}) do
          local value=tonumber(get(prefix..field))
          if value then
            r.SetMediaTrackInfo_Value(guide,field,value)
            put(prefix..field,'');changed=true
          end
        end
      end
    end
    if changed then r.TrackList_AdjustWindows(false);r.UpdateArrange() end
  end
end
if get('cue_ids')=='' and track('phrases') then
  local a,b=bounds()
  if a and b and b>a then
    put('cue_ids','1');put('cue_sequence','1');put('active_cue','1')
    put('cue_1_start',a);put('cue_1_finish',b);put('cue_1_text',get('text'));put('cue_1_speaker','')
    local tr=track('phrases')
    for i=0,r.CountTrackMediaItems(tr)-1 do
      r.GetSetMediaItemInfo_String(r.GetTrackMediaItem(tr,i),'P_EXT:DAD310_ADR_CUE_ID','1',true)
    end
  end
end
r.atexit(function()
  if not r.ValidatePtr or r.ValidatePtr(proj,'ReaProject*') then stop();put('needs_restore','0') end
end)
gfx.init('DAD 310 ADR Cue 0.4.1',1120,780,0)
refresh()
if get('edit_mode')=='1' then notice("Edit mode is active. Click Return to ADR to restore the hidden cue tracks.")
elseif bounds() then notice("Ready. Rehearse plays the guide; Perform and Record silence it at your entrance.") end
frame()
