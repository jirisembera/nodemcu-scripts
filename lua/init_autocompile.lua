--
-- Safe init.lua with auto-compile
--

FILES = {"buffered_socket", "remote_console"}
PRODUCTION = false

for i = 1,#FILES do
    local file_to_execute = FILES[i] .. ".lc"
    local file_to_compile = FILES[i] .. ".lua"
    local file_backup = FILES[i] .. ".lua.bak"

    if file.exists( file_to_compile ) then
        print("Compiling " .. file_to_compile)
        local success, err_msg = pcall(node.compile, file_to_compile)
        if success then
            file.remove(file_backup)
            file.rename(file_to_compile, file_backup)
        else
            print("Failed to compile " .. file_to_compile .. " error: " .. err_msg)
        end
    end

    print("Loading " .. file_to_execute)
    local success, err_msg = pcall(dofile, file_to_execute)
    if not success then
        print("Failed to load " .. file_to_execute .. " error: " .. err_msg)
    end
    collectgarbage()
end
