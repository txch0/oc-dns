-- DNS library
local dns = {}
dns.port = 53

-- Import libraries
local component = require("component")
local encoder = require("serialization")
local event = require("event")

local modem = component.modem

function dns.__splitDomain(domain)
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

function dns.lookup(domain)
    modem.open(dns.port)

    local domainParts = dns.__splitDomain(domain)
    if not domainParts then return end

    modem.broadcast(dns.port, "dns_lookup", encoder.serialize({
        domainParts = domainParts
    }))

    modem.open(dns.port)
    local e, _, address, port, _, response = event.pull(60, "modem_message")
    local result = encoder.unserialize(response)
    modem.close(dns.port)

    if not result then return end
    return result.address
end

function dns.rlookup(address)
    modem.open(dns.port)

    modem.broadcast(dns.port, "dns_rlookup", encoder.serialize({
        address = address
    }))

    modem.open(dns.port)
    local e, _, address, port, _, response = event.pull(60, "modem_message")
    local result = encoder.unserialize(response)
    modem.close(dns.port)

    if not result then return end
    return result.domain
end

function dns.register(domain)
    local address = modem.address
    print(dns.__splitDomain(domain).top)
    
    modem.broadcast(dns.port, "dns_register", encoder.serialize({
        domainParts = dns.__splitDomain(domain),
        address = address
    }))

    modem.open(dns.port)
    local e, _, address, port, _, response = event.pull(60, "modem_message")
    local result = encoder.unserialize(response)
    modem.close(dns.port)

    if not result then return false end
    return result.success
end

local args = { ... }
local command = args[1]

if command == "lookup" then
    print(dns.lookup(args[2]))
elseif command == "rlookup" then
    print(dns.rlookup(args[2]))
elseif command == "register" then   
    local success = dns.register(args[2])
    print(success and "Successfully registered domain." or "An error occured whilst registering this domain.")
end

return dns
