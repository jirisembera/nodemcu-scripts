-- Generates a random string (lower-/upper-case letters, numbers)
-- Based on https://gist.github.com/haggen/2fd643ea9a261fea2094 (updated to run on NodeMCU)

local charset = {}

-- qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890
for i = 48,  57 do table.insert(charset, string.char(i)) end
for i = 65,  90 do table.insert(charset, string.char(i)) end
for i = 97, 122 do table.insert(charset, string.char(i)) end

function random_string(length)
  if length > 0 then
    return random_string(length - 1) .. charset[node.random(1, #charset)]
  else
    return ""
  end
end
