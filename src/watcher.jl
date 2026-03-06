# Layer 3: File watcher — watches notebook file for external changes

using FileWatching

"""
Watch a notebook file for external changes and reload when modified.
Uses polling to allow clean cancellation. Returns a WatcherHandle.
"""
mutable struct WatcherHandle
    task::Task
    running::Threads.Atomic{Bool}
end

function watch_notebook(nb::Notebook, on_change::Function;
                        poll_interval::Float64=1.0)
    path = nb.path
    isfile(path) || error("File not found: $path")

    running = Threads.Atomic{Bool}(true)

    task = @async begin
        last_mtime = mtime(path)
        while running[]
            sleep(poll_interval)
            running[] || break

            current_mtime = mtime(path)
            if current_mtime > last_mtime
                last_mtime = current_mtime
                try
                    on_change(path)
                catch e
                    @warn "Watcher callback error" exception=e
                end
            end
        end
    end

    WatcherHandle(task, running)
end

"""Stop a file watcher."""
function stop_watcher(handle::WatcherHandle)
    handle.running[] = false
    # Wait briefly for the task to finish
    for _ in 1:20
        istaskdone(handle.task) && return
        sleep(0.05)
    end
end
