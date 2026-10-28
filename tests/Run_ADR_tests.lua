-- Run in REAPER. Uses fake project/transport objects; never touches an open project.
local testdir=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local bundle=testdir..'../'
local core=dofile(bundle..'adr_core.lua')
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
 local tracks={{guid='guide',D_VOL=.7,B_MUTE=0}};local ext={guide='guide',start='10',finish='14'}
 local now,state,cursor=0,0,6
 local callback,exitfn,repeatstate=nil,nil,1
 local drawn={}
 local g={w=920,h=580,mouse_x=0,mouse_y=0,mouse_cap=0}
 for _,k in ipairs({'set','setfont','drawstr','rect','circle','update','init','quit'}) do g[k]=function() end end
 g.drawstr=function(s) drawn[#drawn+1]={text=s,y=g.y} end
 g.measurestr=function(s) return #s*8 end;g.getchar=function() return 0 end
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
 local beeps={guid='beeps',B_MUTE=1};tracks[2]=beeps;ext.beeps='beeps'
 local rec
 if options.record then
   rec={guid='record',I_RECARM=options.armed==false and 0 or 1,I_RECINPUT=0,I_RECMODE=0}
   tracks[3]=rec;ext.record='record'
 end
 local olditem={B_MUTE=0}
 api.CountTrackMediaItems=function() return 1 end
 api.GetTrackMediaItem=function() return olditem end
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
   tracks[#tracks+1]={guid='phrases',B_SHOWINTCP=1,B_SHOWINMIXER=1};ext.phrases='phrases'
 end
 local env=setmetatable({reaper=api,gfx=g},{__index=_G})
 assert(loadfile(bundle..'DAD310_ADR_Cue.lua','t',env))()
 local function tick(p) cursor=p or cursor;now=now+.04;callback() end
 local function click(x,y) g.mouse_x=x;g.mouse_y=y;g.mouse_cap=1;tick();g.mouse_cap=0;tick() end
 return {reload=function() assert(loadfile(bundle..'DAD310_ADR_Cue.lua','t',env))() end,tracks=tracks,record=rec,drawn=drawn,hover=function(x,y) g.mouse_x=x;g.mouse_y=y end,clear=function() for i=#drawn,1,-1 do drawn[i]=nil end end,olditem=olditem,state=function() return state end,tick=tick,click=click,guide=tracks[1],beeps=beeps,ext=ext,exit=function() exitfn() end,repeatstate=function() return repeatstate end,externalstop=function() state=0 end}
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
local f=assert(io.open(testdir..'results.txt','w'));f:write(table.concat(result,'\n')..'\n');f:close()
reaper.MB(table.concat(result,'\n'),'ADR Cue tests',0)

for _,line in ipairs(result) do assert(not line:match("^FAIL"),line) end
