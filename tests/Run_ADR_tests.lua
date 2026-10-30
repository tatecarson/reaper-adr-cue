-- Run in REAPER. Uses fake project/transport objects; never touches an open project.
local testdir=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local bundle=testdir..'../'
local core=dofile(bundle..'adr_core.lua')
local editor=dofile(bundle..'adr_text.lua')
local result={}
local function test(name,fn)
 local ok,err=pcall(fn); result[#result+1]=(ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err))
end
test('phrase boundaries preserve punctuation',function()
 local p=assert(core.layout('Wait, please. | Do not go! ',10,14))
 assert(#p==2 and p[1].text=='Wait, please.' and p[2].start==12 and p[2].duration==2)
end)
test('invalid cues rejected',function()
 assert(not core.layout('hello',1,5));assert(not core.layout('hello',5,5));assert(not core.layout(' | ',5,8))
end)
test('count-in and silent fourth beat',function()
 assert(core.phase(6.9,10,14)=='READY');assert(core.phase(7,10,14)=='3')
 assert(core.phase(8,10,14)=='2');assert(core.phase(9,10,14)=='1')
 assert(core.phase(10,10,14)=='SPEAK');assert(core.phase(14,10,14)=='TAIL')
end)
test('seek and loop positions use absolute project time',function()
 assert(core.x(12,12,200,180)==200);assert(core.x(11,12,200,180)==380)
 assert(core.x(13,12,200,180)==20);assert(core.x(11,12,200,180)==380)
end)
test('application parses in REAPER Lua',function() assert(loadfile(bundle..'DAD310_ADR_Cue.lua')) end)
-- Exercise full script with mocks including clicks, callbacks and restoration.
local function session(options)
 options=options or {}
 local tracks={{guid='guide',D_VOL=.7,B_MUTE=0,items={}}};local ext={guide='guide',start='10',finish='14'}
 local now,state,cursor=0,0,6
 local callback,exitfn,repeatstate=nil,nil,1
 local range_a,range_b,input,menu_choice,selected=10,14,nil,0,nil
 local keys={}
 local drawn={}
 local g={w=920,h=580,mouse_x=0,mouse_y=0,mouse_cap=0}
 for _,k in ipairs({'set','setfont','drawstr','rect','circle','update','init','quit'}) do g[k]=function() end end
 g.drawstr=function(s) drawn[#drawn+1]={text=s,y=g.y} end
 g.measurestr=function(s) return #s*8 end;g.getchar=function() return table.remove(keys,1) or 0 end
 local api={}
 api.EnumProjects=function() return 1,'test.RPP' end
 api.GetProjExtState=function(_,_,key) return 1,ext[key] or '' end
 api.SetProjExtState=function(_,_,key,value) ext[key]=value end
 api.CountTracks=function() return #tracks end;api.GetTrack=function(_,i) return tracks[i+1] end
 api.GetTrackGUID=function(tr) return tr.guid end;api.ValidatePtr2=function(_,tr) return tr~=nil end
 api.GetMediaTrackInfo_Value=function(tr,key) return tr[key] or 0 end
 api.SetMediaTrackInfo_Value=function(tr,key,value) tr[key]=value end
 api.GetPlayStateEx=function() return state end;api.GetPlayPositionEx=function() return cursor end
 api.GetCursorPositionEx=function() return cursor end;api.Master_GetPlayRate=function() return 1 end
 api.AnyTrackSolo=function() return false end
 api.GetTrackEnvelopeByName=function() return nil end;api.GetTrackNumSends=function() return 0 end
 api.GetSetRepeatEx=function(_,v) if v>=0 then repeatstate=v end;return repeatstate end
 api.SetEditCurPos2=function(_,p) cursor=p end
 api.OnPlayButtonEx=function() state=1 end;api.OnStopButtonEx=function() state=0 end
 api.time_precise=function() return now end;api.defer=function(fn) callback=fn end
 api.atexit=function(fn) exitfn=fn end;api.MB=function(err) error(err) end
 local beeps={guid='beeps',B_MUTE=1,items={}};tracks[2]=beeps;ext.beeps='beeps'
 local rec
 if options.record then
   rec={guid='record',I_RECARM=options.armed==false and 0 or 1,I_RECINPUT=0,I_RECMODE=0}
   tracks[3]=rec;ext.record='record'
 end
 local olditem={B_MUTE=0}
 if rec then rec.items={olditem} end
 api.CountTrackMediaItems=function(tr) return #(tr.items or {}) end
 api.GetTrackMediaItem=function(tr,i) return (tr.items or {})[i+1] end
 api.InsertTrackAtIndex=function(index) table.insert(tracks,index+1,{guid='track-'..(#tracks+1),items={}}) end
 api.GetSetMediaTrackInfo_String=function(tr,key,value,set) if set then tr[key]=value end;return true,tr[key] or '' end
 api.AddMediaItemToTrack=function(tr) local item={track=tr};tr.items=tr.items or {};tr.items[#tr.items+1]=item;return item end
 api.DeleteTrackMediaItem=function(tr,item) for i,v in ipairs(tr.items) do if v==item then table.remove(tr.items,i);return true end end end
 api.AddTakeToMediaItem=function(item) item.take={};return item.take end
 api.PCM_Source_CreateFromFile=function() return {} end
 api.SetMediaItemTake_Source=function(take,source) take.source=source end
 api.GetSetMediaItemTakeInfo_String=function(take,key,value,set) if set then take[key]=value end;return true,take[key] or '' end
 api.GetSet_LoopTimeRange2=function(_,set,_,a,b) if set then range_a,range_b=a,b end;return range_a,range_b end
 api.GetUserInputs=function() if input==nil then return false,'' end;local value=input;input=nil;return true,value end
 api.GetSelectedTrack=function() return tracks[1] end
 api.GetSelectedMediaItem=function() return selected end
 api.GetMediaItemTrack=function(item) return item.track end
 if not options.system_clipboard then api.CF_GetClipboard=function() return options.clipboard or '' end end
 api.GetOS=function() return options.os or 'OSX64' end
 api.ExecProcess=function(command)
   if options.os=='Win64' then assert(command:find('Get-Clipboard -Raw',1,true))
   else assert(command=='/usr/bin/pbpaste') end
   return options.clipboard_result or '0\n'
 end
 api.GetUserFileNameForRead=function() return false,'' end
 g.showmenu=function() return menu_choice end
 api.GetMediaItemInfo_Value=function(item,key) return item[key] or 0 end
 api.SetMediaItemInfo_Value=function(item,key,value) item[key]=value end
 api.GetSetMediaItemInfo_String=function(item,key,value,set) if set then item[key]=value end;return true,item[key] or '' end
 api.GetToggleCommandStateEx=function(_,id) assert(id==40252);return 1 end
 api.CSurf_OnRecord=function() state=5 end
 api.Undo_BeginBlock2=function() end;api.Undo_EndBlock2=function() end
 api.UpdateArrange=function() end;api.TrackList_AdjustWindows=function() end
 if options.edit then
   tracks[1].B_SHOWINTCP=1;tracks[1].B_SHOWINMIXER=0
   beeps.B_SHOWINTCP=1;beeps.B_SHOWINMIXER=1
   tracks[#tracks+1]={guid='phrases',B_SHOWINTCP=1,B_SHOWINMIXER=1,items=options.legacy and {{D_POSITION=10,D_LENGTH=4,P_NOTES='Legacy words'}} or {}};ext.phrases='phrases'
 end
 local env=setmetatable({reaper=api,gfx=g},{__index=_G})
 assert(loadfile(bundle..'DAD310_ADR_Cue.lua','t',env))()
 local function tick(p) cursor=p or cursor;now=now+.04;callback() end
 local function click(x,y) g.mouse_x=x;g.mouse_y=y;g.mouse_cap=1;tick();g.mouse_cap=0;tick() end
 return {key=function(code,modifiers) g.mouse_cap=modifiers or 0;keys[#keys+1]=code;tick();g.mouse_cap=0 end,input=function(value,a,b) input=value;if a then range_a,range_b=a,b end end,range=function() return range_a,range_b end,select=function(item) selected=item end,menu=function(index) menu_choice=index end,reload=function() assert(loadfile(bundle..'DAD310_ADR_Cue.lua','t',env))() end,tracks=tracks,record=rec,drawn=drawn,hover=function(x,y) g.mouse_x=x;g.mouse_y=y end,clear=function() for i=#drawn,1,-1 do drawn[i]=nil end end,olditem=olditem,state=function() return state end,tick=tick,click=click,guide=tracks[1],beeps=beeps,ext=ext,exit=function() exitfn() end,repeatstate=function() return repeatstate end,externalstop=function() state=0 end}
end
test('perform silences guide on entrance and restores after tail',function()
 local s=session();s.click(490,160);s.tick(9.9);assert(s.guide.D_VOL==.7)
 s.tick(10);assert(s.guide.D_VOL==0 and s.beeps.B_MUTE==0)
 s.tick(15);assert(s.guide.D_VOL==.7 and s.beeps.B_MUTE==1 and s.repeatstate()==1)
 assert(s.ext.needs_restore=='0')
end)
test('rehearsal keeps original audible',function()
 local s=session();s.click(490,122);s.tick(11);assert(s.guide.D_VOL==.7);s.exit()
 assert(s.beeps.B_MUTE==1)
end)
test('backward seek restores guide before entrance',function()
 local s=session();s.click(490,160);s.tick(11);assert(s.guide.D_VOL==0)
 s.tick(8);assert(s.guide.D_VOL==.7);s.exit()
end)
test('external stop and window close restore guide',function()
 local s=session();s.click(490,160);s.tick(11);s.externalstop();s.tick()
 assert(s.guide.D_VOL==.7 and s.beeps.B_MUTE==1)
 local z=session();z.click(490,160);z.tick(11);z.exit()
 assert(z.guide.D_VOL==.7 and z.beeps.B_MUTE==1 and z.repeatstate()==1)
end)
test('record requires the recording track to be armed',function()
 local s=session({record=true,armed=false});s.click(710,122);assert(s.state()==0 and s.beeps.B_MUTE==1)
end)
test('record silences old takes and restores them after stop',function()
 local s=session({record=true});s.click(710,122);assert(s.state()==5 and s.olditem.B_MUTE==1)
 s.tick(11);assert(s.guide.D_VOL==0);s.exit()
 assert(s.olditem.B_MUTE==0 and s.olditem['P_EXT:DAD310_ADR_MUTE']=='')
end)
test('record finishes at tail and clears recovery state',function()
 local s=session({record=true});s.click(710,122);s.tick(15)
 assert(s.state()==0 and s.olditem.B_MUTE==0 and s.ext.needs_restore=='0')
end)
test('tooltips appear after hover delay',function()
 local s=session();s.clear();s.hover(490,122)
 for i=1,32 do s.tick() end
 local found=false
 for _,d in ipairs(s.drawn) do if d.text:find('Practice with the original',1,true) then found=true end end
 assert(found)
end)
test('help pages fit and suppress underlying controls',function()
 local s=session();s.click(850,25)
 for page=1,3 do
   s.clear();s.click(40+(page-1)*220,65)
   local found=false
   for _,d in ipairs(s.drawn) do
     if d.text=='ADR CUE / HELP' then found=true end
     assert(d.y<500,'Help text exceeds window height: '..d.text)
   end
   assert(found)
 end
 s.click(490,160);assert(s.state()==0)
 s.click(800,65);s.click(490,160);s.tick(11);assert(s.guide.D_VOL==0);s.exit()
end)
test('tooltips wait 1.2 seconds and reset after pointer movement',function()
 local s=session();s.clear();s.hover(490,122)
 for i=1,25 do s.tick() end
 for _,d in ipairs(s.drawn) do assert(not d.text:find('Practice with the original',1,true)) end
 s.hover(492,122);s.clear()
 for i=1,25 do s.tick() end
 for _,d in ipairs(s.drawn) do assert(not d.text:find('Practice with the original',1,true)) end
end)
test('tooltips stay hidden during playback',function()
 local s=session();s.click(490,122);s.clear();s.hover(490,122)
 for i=1,40 do s.tick(8) end
 for _,d in ipairs(s.drawn) do assert(not d.text:find('Practice with the original',1,true)) end
 s.exit()
end)
test('Edit mode hides support tracks and preserves recording tracks and video mute',function()
 local s=session({edit=true,record=true});s.click(670,25)
 assert(s.ext.edit_mode=='1' and s.guide.D_VOL==.7 and s.guide.B_MUTE==0)
 assert(s.guide.B_SHOWINTCP==1 and s.guide.B_SHOWINMIXER==0 and s.beeps.B_SHOWINMIXER==0)
 assert(s.record.B_SHOWINTCP==nil and s.record.I_RECARM==1)
 s.click(490,122);assert(s.state()==0)
 s.click(670,25)
 assert(s.ext.edit_mode=='0' and s.guide.D_VOL==.7)
 assert(s.guide.B_SHOWINTCP==1 and s.guide.B_SHOWINMIXER==0)
 assert(s.beeps.B_SHOWINTCP==1 and s.beeps.B_MUTE==1)
end)
test('Edit mode survives closing and reopening the tool',function()
 local s=session({edit=true});s.click(670,25);s.exit()
 assert(s.guide.D_VOL==.7 and s.ext.edit_mode=='1')
 s.reload();s.click(670,25)
 assert(s.guide.D_VOL==.7 and s.guide.B_SHOWINTCP==1 and s.ext.edit_mode=='0')
end)
test('Edit mode cannot interrupt playback',function()
 local s=session({edit=true});s.click(490,122);s.tick(11);s.click(670,25)
 assert(s.state()==1 and s.ext.edit_mode~='1');s.exit()
end)
test('Return to ADR tolerates a deleted support track',function()
 local s=session({edit=true});s.click(670,25);table.remove(s.tracks,2);s.click(670,25)
 assert(s.guide.D_VOL==.7 and s.ext.edit_mode=='0')
end)
test('upgrade restores visibility and scene audio changed by 0.3.0',function()
 local s=session({edit=true});s.click(670,25)
 for i=1,tonumber(s.ext.edit_count) do
   local prefix='edit_'..i..'_'
   if s.ext[prefix..'guid']=='guide' then
     s.ext[prefix..'B_SHOWINTCP']='1';s.ext[prefix..'B_SHOWINMIXER']='0';s.ext[prefix..'D_VOL']='0.7'
   end
 end
 s.guide.B_SHOWINTCP=0;s.guide.B_SHOWINMIXER=0;s.guide.D_VOL=0;s.exit();s.reload()
 assert(s.guide.B_SHOWINTCP==1 and s.guide.B_SHOWINMIXER==0)
 assert(s.guide.D_VOL==.7 and s.ext.edit_mode=='1')
 s.click(670,25);assert(s.guide.D_VOL==.7)
end)
test('return from Edit mode does not change guide visibility',function()
 local s=session({edit=true});s.click(670,25);s.guide.B_SHOWINMIXER=1;s.click(670,25)
 assert(s.guide.B_SHOWINTCP==1 and s.guide.B_SHOWINMIXER==1)
end)
test('whole scene strips bold speaker labels and preserves the spoken names',function()
 local script=[=[**Johnny:** Do you remember one time when we were small, we were out here? It was from right over there. I jumped out at you from behind the tree. And grandpa got all excited, and he shook his fist at me, and he said, “Boy, you’ll be damned to hell.” Remember that? Right over there. Well, you used to really be scared here.
**Barbra:** Johnny.
**Johnny:** Well, you’re still afraid.
**Barbra:** Stop it now. I mean it.
**Johnny:** They’re coming to get you, Barbra.
**Barbra:** Stop it. You’re ignorant.
**Johnny:** They’re coming for you, Barbra.
**Barbra:** Stop it. You’re acting like a child.]=]
 local turns=assert(core.scene_layout(script,10,58))
 assert(#turns==8 and turns[1].speaker=='Johnny' and turns[2].speaker=='Barbra')
 assert(turns[1].text:match('^Do you remember') and turns[2].text=='Johnny.')
 assert(turns[5].text=='They’re coming to get you, Barbra.')
 for _,turn in ipairs(turns) do
   assert(not turn.text:find('**',1,true) and not turn.text:match('^%a+:'))
 end
 assert(turns[1].start==10 and turns[8].finish==58)
 assert(turns[1].finish-turns[1].start>turns[2].finish-turns[2].start)
end)
test('scene handles plain and bold labels, CRLF, continuation lines, and empty turns',function()
 local turns=assert(core.parse_scene('Johnny: Wait. | Please.\r\nAnother sentence.\r\n\r\n**Barbra**: No.'))
 assert(#turns==2 and turns[1].text=='Wait. | Please. Another sentence.' and turns[2].text=='No.')
 assert(not core.parse_scene('Johnny: | '))
 assert(not core.scene_layout('Johnny: Hello',1,10))
 assert(not core.scene_layout('Johnny: Hello',10,10))
end)
local function findtrack(s,key)
 for _,tr in ipairs(s.tracks) do if tr.guid==s.ext[key] then return tr end end
end
test('adding cues preserves other phrases, recording setup, and previous takes',function()
 local s=session({record=true})
 s.input('Johnny: First | line.',10,14);s.click(50,122)
 local tr=findtrack(s,'phrases');local first=tr.items[1]
 assert(#tr.items==2 and s.ext.active_cue=='1' and first.P_NOTES=='First')
 s.input('Barbra: Second line.',30,35);s.click(50,122)
 assert(#tr.items==3 and tr.items[1]==first and s.ext.cue_ids=='1,2')
 assert(s.record.I_RECARM==1 and s.olditem.B_MUTE==0)
 assert(s.ext.cue_2_speaker=='Barbra' and s.ext.start=='30')
 for i,item in ipairs(s.beeps.items) do assert(item.D_POSITION==30-4+i) end
 s.click(170,58)
 assert(s.ext.active_cue=='1' and s.ext.start=='10' and #tr.items==3)
 for i,item in ipairs(s.beeps.items) do assert(item.D_POSITION==10-4+i) end
 s.click(850,58);assert(s.ext.active_cue=='2')
end)
test('whole scene preview appends cues, with cancellation and no underlying button actions',function()
 local s=session({clipboard='**Johnny:** One. | Two.\n**Barbra:** Johnny.'})
 s.input('Existing cue',10,14);s.click(50,122)
 s.input(nil,20,40);s.click(50,58);s.click(50,90)
 assert(s.ext.cue_ids=='1')
 s.click(50,122);assert(s.ext.cue_ids=='1','click leaked through import overlay')
 s.click(500,90)
 assert(s.ext.cue_ids=='1,2,3' and s.ext.active_cue=='2')
 local tr=findtrack(s,'phrases');assert(#tr.items==4)
 assert(tr.items[2].P_NOTES=='One.' and tr.items[4].P_NOTES=='Johnny.')
 s.click(50,58);s.click(750,90);assert(s.ext.cue_ids=='1,2,3')
end)
test('cue selection survives reload, sorts by time, and is blocked during playback',function()
 local s=session()
 s.input('Late',30,35);s.click(50,122)
 s.input('Early',10,15);s.click(50,122)
 s.reload();s.menu(2);s.click(300,58)
 assert(s.ext.active_cue=='1' and s.ext.start=='30')
 local a,b=s.range();assert(a==30 and b==35)
 s.click(490,122);assert(s.state()==1)
 s.click(170,58);assert(s.ext.active_cue=='1')
 s.exit();s.click(170,58);assert(s.ext.active_cue=='2')
end)
test('Use range changes only the active cue and beeps, preserving phrase positions',function()
 local s=session()
 s.input('One',10,14);s.click(50,122)
 s.input('Two',30,35);s.click(50,122)
 local tr=findtrack(s,'phrases');local pos=tr.items[2].D_POSITION
 s.input(nil,32,37);s.click(270,160)
 assert(s.ext.cue_2_start=='32' and s.ext.cue_2_finish=='37' and s.ext.cue_1_start=='10')
 assert(tr.items[2].D_POSITION==pos and s.beeps.items[1].D_POSITION==29)
 s.click(170,58);s.click(850,58);assert(s.ext.start=='32')
end)
test('only the active cue scrolls and speaker labels stay in the cue list',function()
 local s=session()
 s.input('Johnny: FIRST_ONLY',10,14);s.click(50,122)
 s.input('Barbra: SECOND_ONLY',30,35);s.click(50,122)
 s.clear();s.tick()
 local scrolling={}
 for _,d in ipairs(s.drawn) do if d.y==309 or d.y==375 then scrolling[#scrolling+1]=d.text end end
 assert(#scrolling==1 and scrolling[1]=='SECOND_ONLY')
end)
test('legacy cue upgrades without moving or replacing its phrase items',function()
 local s=session({edit=true,legacy=true})
 local legacy=findtrack(s,'phrases').items[1]
 assert(legacy.D_POSITION==10 and legacy.D_LENGTH==4 and legacy.P_NOTES=='Legacy words')
 assert(legacy['P_EXT:DAD310_ADR_CUE_ID']=='1')
 assert(s.ext.cue_ids=='1' and s.ext.cue_1_start=='10' and s.ext.cue_1_finish=='14')
 s.input('New',30,34);s.click(50,122)
 assert(s.ext.cue_ids=='1,2' and findtrack(s,'phrases').items[1]==legacy)
end)
test('scene paste uses system clipboard without SWS on macOS and Windows',function()
 for _,osname in ipairs({'OSX64','Win64'}) do
   local s=session({system_clipboard=true,os=osname,clipboard_result='0\n**Johnny:** Hello.\r\n**Barbra:** No.'})
   s.click(50,58);s.click(50,90);s.click(500,90)
   assert(s.ext.cue_ids=='1,2' and s.ext.cue_1_speaker=='Johnny')
 end
end)
test('failed clipboard and invalid scene imports leave the session untouched',function()
 local s=session({system_clipboard=true,clipboard_result='1\nfailed'})
 s.click(50,58);s.click(50,90);s.click(500,90)
 assert(not s.ext.cue_ids and #s.tracks==2)
 s.click(750,90)
 s.input(nil,0,2);s.click(50,58)
 assert(not s.ext.cue_ids and #s.tracks==2)
end)
test('large scene editor inserts breaks at a clicked position before creating cues',function()
 local s=session({clipboard='Johnny: Hello there.'})
 s.click(50,58);s.click(50,90)
 -- Editor text starts at x32, y210; mock character width is eight pixels.
 s.click(32+14*8,212);s.key(124)
 s.click(500,90)
 assert(s.ext.cue_1_text=='Hello |there.')
 local tr=findtrack(s,'phrases')
 assert(#tr.items==2 and tr.items[1].P_NOTES=='Hello' and tr.items[2].P_NOTES=='there.')
end)
test('scene editor typing, selection, paste, and undo do not trigger transport',function()
 local s=session({clipboard='Johnny: Hello'})
 s.click(50,58);s.click(50,90)
 s.key(1);s.key(22)
 s.key(32);s.key(124);s.key(32);s.key(88);s.key(26)
 s.click(500,90)
 assert(s.state()==0 and s.ext.cue_1_text=='Hello |')
end)
test('text editor edits Unicode, replaces selection, and supports undo and redo',function()
 local e={};editor.set(e,'Barbra: You’re here.')
 local quote=assert(e.text:find('’',1,true))
 editor.move(e,quote-1,false);editor.move(e,editor.following(e.text,e.caret),true)
 editor.insert(e,"'");assert(e.text=="Barbra: You're here.")
 editor.undo(e);assert(e.text=='Barbra: You’re here.')
 editor.undo(e,true);assert(e.text=="Barbra: You're here.")
 editor.move(e,0,false);editor.erase(e,true);assert(e.text=="Barbra: You're here.")
 editor.set(e,'é');editor.erase(e,true);assert(e.text=='');editor.undo(e);assert(e.text=='é')
end)
test('soft wrapping preserves script bytes and newline boundaries',function()
 local value='Johnny: One | two three.\n\nBarbra: é.'
 local rows=editor.rows(value,12)
 local last=-1
 for _,row in ipairs(rows) do
   assert(row.start>=last and row.text==value:sub(row.start+1,row.finish))
   assert(utf8.len(row.text))
   last=row.finish
 end
 assert(rows[#rows].finish==#value)
 for pos=0,#value do
   if pos==0 or value:byte(pos)<128 or value:byte(pos)>=192 then
     -- row lookup always returns an existing visual line.
     assert(rows[editor.row_at(rows,pos)])
   end
 end
 local e={};editor.set(e,'Johnny: A\r\nBarbra: B');assert(e.text=='Johnny: A\nBarbra: B')
end)
local f=assert(io.open(testdir..'results.txt','w'));f:write(table.concat(result,'\n')..'\n');f:close()
reaper.MB(table.concat(result,'\n'),'ADR Cue tests',0)

for _,line in ipairs(result) do assert(not line:match("^FAIL"),line) end
