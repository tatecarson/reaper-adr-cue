-- DAD 310 ADR Cue 0.3.0. Load this file through Actions > New action > Load ReaScript.
-- No SWS, ReaImGui, web server, or compiled plugin required.
local r = reaper
if r.set_action_options then r.set_action_options(1) end
local dir = debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local core = dofile(dir .. 'adr_core.lua')
local proj = r.EnumProjects(-1, '')
local NS = 'DAD310_ADR_CUE_V1'
local run, previous_mouse, message = nil, 0, 'Select the line in time, then click New line.'
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
local function refresh()
  phrases={}
  local tr=track('phrases')
  if tr then
    for i=0,r.CountTrackMediaItems(tr)-1 do
      local item=r.GetTrackMediaItem(tr,i)
      local _,text=r.GetSetMediaItemInfo_String(item,'P_NOTES','',false)
      phrases[#phrases+1]={item=item,text=text,start=r.GetMediaItemInfo_Value(item,'D_POSITION'),duration=r.GetMediaItemInfo_Value(item,'D_LENGTH')}
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
    if r.GetTrackEnvelopeByName(guide,'Volume') or r.GetTrackNumSends(guide,0)>0 or r.GetTrackNumSends(guide,1)>0 then
      notice('Guide must have no volume automation or sends before Edit mode can silence it.'); return
    end
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
            put(prefix..field,r.GetMediaTrackInfo_Value(tr,field))
            r.SetMediaTrackInfo_Value(tr,field,0)
          end
          -- Store only properties changed by this mode; leave the video enabled.
          put(prefix..'D_VOL','');put(prefix..'B_MUTE','')
          if key=='guide' then
            put(prefix..'D_VOL',r.GetMediaTrackInfo_Value(tr,'D_VOL'))
            r.SetMediaTrackInfo_Value(tr,'D_VOL',0)
          elseif key=='beeps' then
            put(prefix..'B_MUTE',r.GetMediaTrackInfo_Value(tr,'B_MUTE'))
            r.SetMediaTrackInfo_Value(tr,'B_MUTE',1)
          end
        end
      end
      put('edit_count',count);put('edit_mode','1')
    end
    r.TrackList_AdjustWindows(false)
  end)
  notice(editing and 'ADR tracks restored. Rehearse or record when ready.' or 'Edit mode: support tracks hidden and guide silent. Edit your takes in REAPER. Return to ADR restores the previous track settings.')
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
local function new_line()
  if not stopped() then return end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  local ok,text=r.GetUserInputs('Dialogue: separate phrases with |',1,'Dialogue,extrawidth=320',get('text'))
  if not ok then return end
  local layout,err=core.layout(text,a,b)
  if not layout then notice(err); return end
  if track('phrases') and r.MB('Replace the current cue and phrase items? Recorded takes remain.','New ADR line',4)~=6 then return end
  undo('Create ADR line',function()
    local tr=ensure('phrases','ADR PHRASES - move items to match the guide')
    for i=r.CountTrackMediaItems(tr)-1,0,-1 do r.DeleteTrackMediaItem(tr,r.GetTrackMediaItem(tr,i)) end
    for _,p in ipairs(layout) do
      local item=r.AddMediaItemToTrack(tr)
      r.SetMediaItemInfo_Value(item,'D_POSITION',p.start)
      r.SetMediaItemInfo_Value(item,'D_LENGTH',p.duration)
      r.SetMediaItemInfo_Value(item,'C_BEATATTACHMODE',0)
      r.GetSetMediaItemInfo_String(item,'P_NOTES',p.text,true)
    end
    put('start',a); put('finish',b); put('text',text)
    make_beeps(a)
    local existing=track('record')
    local rec=ensure('record','ADR RECORD - choose microphone input')
    if not existing then
    r.SetMediaTrackInfo_Value(rec,'I_RECARM',0)
    r.SetMediaTrackInfo_Value(rec,'I_RECMODE',0)
    r.SetMediaTrackInfo_Value(rec,'I_RECINPUT',-1)
    r.SetMediaTrackInfo_Value(rec,'I_RECMON',0)
    end
  end)
  refresh()
  notice('Move phrase items to match speech. Select the picture/guide track, then Set guide.')
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
  local _,old=r.GetSetMediaItemInfo_String(item,'P_NOTES','',false)
  local ok,text=r.GetUserInputs('Edit phrase',1,'Text,extrawidth=320',old)
  if ok and text:match('%S') then undo('Edit ADR phrase',function() r.GetSetMediaItemInfo_String(item,'P_NOTES',text,true) end); refresh() end
end
local function update_bounds()
  if not stopped() then return end
  local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
  if a<4 or b<=a then notice('Select a line range starting at least four seconds into the project.'); return end
  if not track('phrases') then notice('Create a line first.'); return end
  undo('Update ADR cue range',function() put('start',a);put('finish',b);make_beeps(a) end)
  notice('Cue range updated. Phrase positions stay where you placed them.')
end
local help_open,help_page=false,1
local hover_id,hover_since=nil,0
local hover_x,hover_y=nil,nil
local tips={
  ['New line']='Create phrases from the time selection.',
  ['Set guide']='Use the selected track as the original dialogue.',
  ['Edit phrase']="Change the selected phrase item's text.",
  ['Use range']='Update cue timing from the time selection.',
  ['Rehearse']='Practice with the original. Does not record.',
  ['Perform']='Practice without the original. Does not record.',
  ['Record']='Record onto the armed ADR RECORD track.',
  ['Stop']='Stop and restore guide and take levels.',
  ['Edit in REAPER']='Hide cue/guide tracks and silence the guide.',
  ['Return to ADR']='Restore the previous track visibility and guide level.',
  ['Help']='Setup, recording, and troubleshooting.'
}
local help_pages={
  {title='1 / Set up and sync',body={
    'Save the project. Import your video and place it at 10 seconds to leave room for the count-in.',
    'Drag a time selection in the ruler over the spoken line. Selecting the video item alone is not enough.',
    'Click New line. Use | between phrases, for example: Wait a second. | I left my keys | on the table.',
    'Select the original dialogue track and click Set guide. Clear all track solos.',
    'New line spaces phrases evenly; it does not detect speech. Move each ADR PHRASES item to the phrase onset and trim its end. Turn off snapping for precise edits.',
    'Speak when the phrase reaches the FIXED GREEN LINE. The amber strip above the words is only the count-in. Use shorter phrases for finer timing.'}},
  {title='2 / Rehearse, record, review',body={
    'Rehearse: hear the original and practice its rhythm. Perform: practice with the guide silenced at the entrance. Neither records.',
    'For Record: save the project, choose your microphone input on ADR RECORD, arm that track, and disarm all other tracks. Use normal record mode and headphones.',
    "Click Record HERE, not on REAPER's transport, for automatic guide control. Hear three beeps; speak on the silent fourth beat. Recording stops one second after the line.",
    'Previous ADR RECORD items are silenced during each run and restored afterward. Use Record again for another take. Keep the files if REAPER asks.',
    "Click Edit in REAPER to hide cue/guide tracks and silence the guide. Comp in fixed item lanes; Return to ADR restores visibility and guide level.",
    'Space toggles rehearsal/stop in the cue window. In Help, Space only stops an active run. Escape closes Help; a second Escape closes the tool.'}},
  {title='3 / If something does not work',body={
    'Nothing starts? Read the status message below the cues. Clear solos, unmute the guide, and set project playback rate to 1.0.',
    'Four-second warning? The time selection must start at least four seconds into the project. Move the video later and select the spoken line again.',
    'Words out of sync? Move phrase items to match the original. Only phrase beginnings are timed; words within each phrase are not aligned individually.',
    "Original audible while recording? Use this window's Record button and assign the correct guide. Check for another copy playing on a different track.",
    'No microphone? Choose an input and arm ADR RECORD. Enable input monitoring only if needed. Guide tracks must have no volume automation or sends.',
    'Stop before mixing or rendering and keep ADR COUNT-IN muted. Cue settings save with the project. One active line is supported; New line replaces its cues.'}}
}
local buttons={
  {'New line',new_line},{'Set guide',set_guide},{'Edit phrase',edit_phrase},{'Use range',update_bounds},
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
  color(.93,.91,.85);text(20,16,'ADR CUE',24)
  color(.60,.68,.69);text(20,46,'DAD 310  /  One line to picture',14)
  local mouse=gfx.mouse_cap&1
  local pressed=mouse==1 and previous_mouse==0
  local hovered=nil
  local help_hover=inside(w-100,14,80,30)
  color(help_hover and .27 or .17,.23,.24);gfx.rect(w-100,14,80,30,true)
  color(.95,.94,.89);text(w-83,21,'Help ?',15)
  if not help_open and help_hover then
    hovered='Help'
    if pressed then help_open=true end
  end
  local edit_label=get('edit_mode')=='1' and 'Return to ADR' or 'Edit in REAPER'
  local edit_hover=inside(w-280,14,168,30)
  color(.18,edit_hover and .30 or .24,.31);gfx.rect(w-280,14,168,30,true)
  color(.95,.94,.89);text(w-270,21,edit_label,15)
  if not help_open and edit_hover then
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
      if hover and not help_open then
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
  if get('edit_mode')=='1' then detail='Guide silent / cue tracks hidden / recordings available in REAPER' end
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
  if help_open then
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
  local key=gfx.getchar()
  if key<0 then stop();gfx.quit();return end
  if key==27 then
    if help_open then help_open=false else stop();gfx.quit();return end
  end
  if key==63 then help_open=not help_open end
  if key==32 then if run then stop() elseif not help_open then start('Rehearse') end end
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
r.atexit(function()
  if not r.ValidatePtr or r.ValidatePtr(proj,'ReaProject*') then stop();put('needs_restore','0') end
end)
gfx.init('DAD 310 ADR Cue',960,580,0)
refresh()
if get('edit_mode')=='1' then notice("Edit mode is active. Click Return to ADR to restore the hidden tracks and guide level.")
elseif bounds() then notice("Ready. Rehearse plays the guide; Perform and Record silence it at your entrance.") end
frame()
