-- DNS SERVER
local port = 53
local dns_dir = "usr/dns_records"

-- Import libraries
local fs = require("filesystem")
local component = require("component")
local encoder = require("serialization")
local event = require("event")

local modem = component.modem

local dnsRecords = {}
local rdnsRecords = {}

function splitDomain(domain)
    local parts = string.gmatch(domain, "([^.]+)")
    local partTable = {}
    
    for part in parts do
        table.insert(partTable, part)
    end

    if #partTable ~= 3 then return error("Invalid domain provided.") end

    return {
        sub = partTable[1],
        name = partTable[2],
        top = partTable[3]
    }
end

function lookup(domainParts)
    if dnsRecords[domainParts.top] == nil then return end
    if dnsRecords[domainParts.top][domainParts.name] == nil then return end
    if dnsRecords[domainParts.top][domainParts.name][domainParts.sub] == nil then return end

    return dnsRecords[domainParts.top][domainParts.name][domainParts.sub]
end

function rlookup(address)
    print(rdnsRecords[address])
    if rdnsRecords[address] == nil then return end
    return encoder.serialize(rdnsRecords[address])
end

function register(domainParts, address)
    if dnsRecords[domainParts.top] == nil then
        print("DNS> Registering new domain top level:", domainParts.top) 
        dnsRecords[domainParts.top] = {} 
    end
    
    if dnsRecords[domainParts.top][domainParts.name] ~= nil then
        if dnsRecords[domainParts.top][domainParts.name][domainParts.sub] ~= nil then
            print("DNS> Registering failed: Exact domain already exists.")
            return false
        end

        dnsRecords[domainParts.top][domainParts.name][domainParts.sub] = address
    else
        dnsRecords[domainParts.top][domainParts.name] = {
            [domainParts.sub] = address
        }
    end

    local topLevelFile = fs.open(dns_dir .. "/" .. domainParts.top, "w")
    local success = topLevelFile:write(encoder.serialize(dnsRecords[domainParts.top]))
    topLevelFile:close()
    print("DNS> Saved registry file: ", success)
    return success or false
end

function load_registries()
    if not fs.exists(dns_dir) then
        fs.makeDirectory(dns_dir)
    end

    local toplevels = fs.list(dns_dir)

    if toplevels ~= nil then
        for topLevel in toplevels do
            local topLevelDir = dns_dir .. "/" .. topLevel
            local file = fs.open(topLevelDir)
            if not file then
                print("DNS> Failed to open registry file: " .. topLevel)
                goto continue
            end
            
            local topLevelName = fs.name(topLevelDir)
            dnsRecords[topLevelName] = {}

            local data = file:read(fs.size(topLevelDir))
            local decodedData = encoder.unserialize(data)
            if decodedData ~= nil then
                for name, subs in pairs(decodedData) do
                    for sub, address in pairs(subs) do
                        if dnsRecords[topLevelName][name] ~= nil then
                            dnsRecords[topLevelName][name][sub] = address
                        else
                            dnsRecords[topLevelName][name] = {
                                [sub] = address
                            }
                        end
    
                        if rdnsRecords[address] ~= nil then
                            table.insert(rdnsRecords[address], sub .. "." .. name .. "." .. topLevelName)
                        else
                            rdnsRecords[address] = { sub .. "." .. name .. "." .. topLevelName }
                        end
                    end
                end
            end
            file:close()
            ::continue::
        end
    end
end

function startup()
    print("DNS> Starting server...")
    while true do
        modem.open(port)
        local e, _, address, port, _, trafficType, request = event.pull("modem_message")
        request = encoder.unserialize(request)
        if request and (trafficType == "dns_lookup") then
            print("DNS> Received lookup request.")
            modem.send(address, port, encoder.serialize({
                address = lookup(request.domainParts)
            }))
        elseif request and (trafficType == "dns_rlookup") then
            print("DNS> Received rlookup request.")
            modem.send(address, port, rlookup(request.address))
        elseif request and (trafficType == "dns_register") then
            print("DNS> Received registry request.")
            modem.send(address, port, encoder.serialize({
                success = register(request.domainParts, address)
            }))
        end
    end
end

local args = { ... }
load_registries()

for a, b in pairs(rdnsRecords) do print(a,b) end

if args[1] == "start" then
    startup()
elseif args[2] == "register" then
    local domain = args[3]
    if not domain then return error("No domain provided.") end

    local domainParts = splitDomain(domain)
    if not domainParts then return error("No valid domain provided.") end

    local address = args[4]
    if not address then return error("No address provided.") end

    local success = register(domainParts, address)
    print(success and "Successfully registered domain." or "An error occured whilst registering this domain.")
end
