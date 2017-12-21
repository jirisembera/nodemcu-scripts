--
-- Sample init.lua with auto-compile: Develop using .lua sources, run compiled bytecode (.lc) in production
-- 
-- Usage:
--   * List files to be executed in the FILES table !! without extension !!
--   * Set PRODUCTION = false for development
--   * Change to PRODUCTION = true for production deployment. ".lc" files get auto-recompiled on the first production run and then re-used
--

FILES = {"buffered_socket", "remote_console"}
PRODUCTION = false

for i = 1,#FILES do
    local file_to_execute = nil

    if PRODUCTION then
        file_to_execute = FILES[i] .. ".lc"
        if not file.exists( file_to_execute ) then
            node.compile( FILES[i] .. ".lua" )
        end
    else
        file_to_execute = FILES[i] .. ".lua"
        local file_to_remove = FILES[i] .. ".lc"
        if file.exists( file_to_remove ) then
            file.remove( file_to_remove )
        end
    end
    
    local success, err_msg = pcall(dofile, file_to_execute)
    if not success then
        print("Failed to load " .. file_to_execute .. " error: " .. err_msg)
    end
end
