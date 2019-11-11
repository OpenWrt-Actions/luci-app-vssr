-- Copyright (C) 2018 jerrykuku <jerrykuku@qq.com>
-- Licensed to the public under the GNU General Public License v3.

module("luci.controller.vssr", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/vssr") then
        return
    end

    if nixio.fs.access("/usr/bin/ssr-redir") then
        entry({"admin", "services", "vssr"},alias("admin", "services", "vssr", "client"), _("vssr"),10).dependent = true                                  -- 首页
        entry({"admin", "services", "vssr", "client"},cbi("vssr/client"),_("SSR Client"),10).leaf = true                                                  -- 基本设置
        entry({"admin", "services", "vssr", "servers"},cbi("vssr/servers"), _("Severs Nodes"), 11).leaf = true                                           -- 服务器节点
        entry({"admin", "services", "vssr", "servers"},arcombine(cbi("vssr/servers"), cbi("vssr/client-config")),_("Severs Nodes"), 11).leaf = true       -- 编辑节点
        entry({"admin", "services", "vssr", "control"},cbi("vssr/control"),_("Access Control"),12).leaf = true                                            -- 访问控制
        if nixio.fs.access("/usr/bin/v2ray/v2ray") then
        entry({"admin", "services", "vssr", "socks5"},cbi("vssr/socks5"),_("Socks5"),13).leaf = true                                                      -- Socks5代理
        end
        entry({"admin", "services", "vssr", "advanced"},cbi("vssr/advanced"), _("Advanced Settings"),14).leaf = true                                      -- 高级设置
    elseif nixio.fs.access("/usr/bin/ssr-server") then
        entry({"admin", "services", "vssr"},alias("admin", "services", "vssr", "server"), _("vssr"),10).dependent = true
    else
        return
    end

    if nixio.fs.access("/usr/bin/ssr-server") then
        entry({"admin", "services", "vssr", "server"},arcombine(cbi("vssr/server"), cbi("vssr/server-config")),_("SSR Server"),20).leaf = true
    end

    entry({"admin", "services", "vssr", "log"}, cbi("vssr/log"), _("Log"), 30).leaf = true


    entry({"admin", "services", "vssr", "refresh"}, call("refresh_data"))     -- 更新白名单和GFWLIST
    entry({"admin", "services", "vssr", "checkport"}, call("check_port"))     -- 检测单个端口并返回Ping
    entry({"admin", "services", "vssr", "run"}, call("act_status"))           -- 检测全局服务器状态
    entry({"admin", "services", "vssr", "change"}, call("change_node"))       -- 切换节点
    entry({"admin", "services", "vssr", "allserver"}, call("get_servers"))    -- 获取所有节点Json
	entry({"admin", "services", "vssr", "subscribe"}, call("get_subscribe"))  -- 执行订阅
	entry({"admin", "services", "vssr", "flag"}, call("get_flag"))            -- 获取节点国旗 iso code
end

-- 执行订阅
function get_subscribe()

	local cjson = require "cjson"
    local e={}
    local uci = luci.model.uci.cursor()
    local auto_update = luci.http.formvalue("auto_update")
    local auto_update_time = luci.http.formvalue("auto_update_time")
    local proxy = luci.http.formvalue("proxy")
    local subscribe_url = luci.http.formvalue("subscribe_url")
	if  subscribe_url ~= "[]" then
		local cmd1 = 'uci set vssr.@server_subscribe[0].auto_update="'..auto_update..'"'
		local cmd2 = 'uci set vssr.@server_subscribe[0].auto_update_time="'..auto_update_time..'"'
		local cmd3 = 'uci set vssr.@server_subscribe[0].proxy="'..proxy..'"'
		luci.sys.call('uci delete vssr.@server_subscribe[0].subscribe_url ')
		luci.sys.call(cmd1)
		luci.sys.call(cmd2)
		luci.sys.call(cmd3)
		for k,v in ipairs(cjson.decode(subscribe_url)) do
			luci.sys.call('uci add_list vssr.@server_subscribe[0].subscribe_url="'..v..'"')
		end
		luci.sys.call('uci commit vssr')
		luci.sys.call("nohup /usr/share/vssr/subscribe.sh >/www/check_update.htm 2>/dev/null &")
		e.error = 0;
	else
		e.error = 1;
	end	
	
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
	
end


-- 获取所有节点
function get_servers()
    local uci = luci.model.uci.cursor()
    local server_table = {}
    uci:foreach("vssr", "servers", function(s)
        s["name"] = s[".name"]
        table.insert(server_table,s)
    end)
    luci.http.prepare_content("application/json")
    luci.http.write_json(server_table)
end



-- 切换节点
function change_node()
    local e={}
    local uci = luci.model.uci.cursor()
    local sid = luci.http.formvalue("set")
    local name = ""
    uci:foreach("vssr", "global", function(s)
        name = s[".name"]
    end)
    e.status = false
	e.sid = sid
    if sid ~= "" then
    uci:set("vssr", name, "global_server" , sid)
	uci:commit("vssr")
    luci.sys.call("/etc/init.d/vssr restart")
    e.status = true
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end



-- 检测全局服务器状态
function act_status()
	math.randomseed(os.time())
    local e={}
    --全局服务器
    e.global=luci.sys.call("busybox ps -w | grep vssr_t | grep -v grep >/dev/null") == 0  
    --检测PDNSD状态
    e.pdnsd=luci.sys.call("pidof pdnsd >/dev/null") == 0   
    -- 检测游戏模式状态
    e.game = luci.sys.call("busybox ps -w | grep vssr_u | grep -v grep >/dev/null") == 0

    
    -- 检测国外通道
    http=require("socket.http")
	http.TIMEOUT = 1
	result=http.request("http://ip111cn.appspot.com/?z="..math.random(1,100000))
	if result then
		e.google = result
	else
		e.google = false
	end
	
	result1=http.request("http://45.32.164.128/ip.php?z="..math.random(1,100000))
	if result1 then
		e.outboard = result1
	else
		e.outboard = false
	end
	
	
	
	-- 检测Socks5
	e.socks5=luci.sys.call("busybox ps -w | grep vssr_s | grep -v grep >/dev/null") == 0
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end


-- 刷新检测文件
function refresh_data()
    local set = luci.http.formvalue("set")
    local icount = 0

    if set == "gfw_data" then
        if nixio.fs.access("/usr/bin/wget-ssl") then
            refresh_cmd =
                "wget-ssl --no-check-certificate https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt -O /tmp/gfw.b64"
        else
            refresh_cmd = "wget -O /tmp/gfw.b64 http://iytc.net/tools/list.b64"
        end
        sret = luci.sys.call(refresh_cmd .. " 2>/dev/null")
        if sret == 0 then
            luci.sys.call("/usr/bin/ssr-gfw")
            icount = luci.sys.exec("cat /tmp/gfwnew.txt | wc -l")
            if tonumber(icount) > 1000 then
                oldcount = luci.sys.exec("cat /etc/dnsmasq.ssr/gfw_list.conf | wc -l")
                if tonumber(icount) ~= tonumber(oldcount) then
                    luci.sys.exec("cp -f /tmp/gfwnew.txt /etc/dnsmasq.ssr/gfw_list.conf")
                    retstring = tostring(math.ceil(tonumber(icount) / 2))
                else
                    retstring = "0"
                end
            else
                retstring = "-1"
            end
            luci.sys.exec("rm -f /tmp/gfwnew.txt ")
        else
            retstring = "-1"
        end
    elseif set == "ip_data" then
        refresh_cmd =
            'wget -O- \'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest\'  2>/dev/null| awk -F\\| \'/CN\\|ipv4/ { printf("%s/%d\\n", $4, 32-log($5)/log(2)) }\' > /tmp/china_ssr.txt'
        sret = luci.sys.call(refresh_cmd)
        icount = luci.sys.exec("cat /tmp/china_ssr.txt | wc -l")
        if sret == 0 and tonumber(icount) > 1000 then
            oldcount = luci.sys.exec("cat /etc/china_ssr.txt | wc -l")
            if tonumber(icount) ~= tonumber(oldcount) then
                luci.sys.exec("cp -f /tmp/china_ssr.txt /etc/china_ssr.txt")
                retstring = tostring(tonumber(icount))
            else
                retstring = "0"
            end
        else
            retstring = "-1"
        end
        luci.sys.exec("rm -f /tmp/china_ssr.txt ")
    else
        if nixio.fs.access("/usr/bin/wget-ssl") then
            refresh_cmd =
                "wget --no-check-certificate -O - https://easylist-downloads.adblockplus.org/easylistchina+easylist.txt | grep ^\\|\\|[^\\*]*\\^$ | sed -e 's:||:address\\=\\/:' -e 's:\\^:/127\\.0\\.0\\.1:' > /tmp/ad.conf"
        else
            refresh_cmd = "wget -O /tmp/ad.conf http://iytc.net/tools/ad.conf"
        end
        sret = luci.sys.call(refresh_cmd .. " 2>/dev/null")
        if sret == 0 then
            icount = luci.sys.exec("cat /tmp/ad.conf | wc -l")
            if tonumber(icount) > 1000 then
                if nixio.fs.access("/etc/dnsmasq.ssr/ad.conf") then
                    oldcount = luci.sys.exec("cat /etc/dnsmasq.ssr/ad.conf | wc -l")
                else
                    oldcount = 0
                end

                if tonumber(icount) ~= tonumber(oldcount) then
                    luci.sys.exec("cp -f /tmp/ad.conf /etc/dnsmasq.ssr/ad.conf")
                    retstring = tostring(math.ceil(tonumber(icount)))
                    if oldcount == 0 then
                        luci.sys.call("/etc/init.d/dnsmasq restart")
                    end
                else
                    retstring = "0"
                end
            else
                retstring = "-1"
            end
            luci.sys.exec("rm -f /tmp/ad.conf ")
        else
            retstring = "-1"
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({ret = retstring, retcount = icount})
end



-- 检测单个节点状态并返回连接速度
function check_port()

    local e={}
    --e.index=luci.http.formvalue("host")
    local t1 =luci.sys.exec("ping -c 1 -W 1 %q 2>&1 | grep -o 'time=[0-9]*.[0-9]' | awk -F '=' '{print$2}'"%luci.http.formvalue("host"))
    luci.http.prepare_content("application/json")
    luci.http.write_json({ret = 1 , used = t1})

    
--[[local sockets = require "socket"
    local set = luci.http.formvalue("host")
    local port = luci.http.formvalue("port")
    local retstring = ""
    local iret = 1
    iret = luci.sys.call(" ipset add ss_spec_wan_ac " .. set .. " 2>/dev/null")
    socket = nixio.socket("inet", "stream")
    socket:setopt("socket", "rcvtimeo", 3)
    socket:setopt("socket", "sndtimeo", 3)
    local t0 = sockets.gettime()
    ret = socket:connect(set, port)
    if tostring(ret) == "true" then
        socket:close()
        retstring = "1"
    else
        retstring = "0"
    end
    if iret == 0 then
        luci.sys.call(" ipset del ss_spec_wan_ac " .. set)
    end
    local t1 = sockets.gettime()
    local tt =t1 -t0
    luci.http.prepare_content("application/json")
    luci.http.write_json({ret = retstring , used = math.floor(tt*1000 + 0.5)})
    
--]]
end

-- 获取节点国旗 iso code
function get_flag()
    local e={}
    local host = luci.http.formvalue("host")
    local cmd1 = '/usr/share/vssr/getflag.sh '..host
    e.host=host
    e.flag=luci.sys.exec(cmd1)
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end