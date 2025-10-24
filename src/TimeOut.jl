module TimeOut

import Base.Threads.@spawn
import Genie.Util.killtask

export timeout, @timeout, killtask

function _killtimer(@nospecialize(interval), abort_channel::Channel{Bool}, result_channel::Channel{Any}, @nospecialize(failed))
    Timer(interval) do _
        if failed isa Function
            put!(result_channel, try
                failed() # check if it throws
            catch e
                e # if it does, return the error to be rethrown in the main task
            end)
        else
            put!(result_channel, failed)
        end
        put!(abort_channel, true)
    end
end

function timeout(@nospecialize(f::Base.Callable), @nospecialize(interval), ::Type{T} = Any;
    @nospecialize(failed), @nospecialize(abort_msg::AbstractString = "")
) where T
    result_channel = Channel(1)
    abort_channel = Channel{Bool}(1)
    task_channel = Channel{Task}(1)

    task = @spawn try
        inner_task = @async put!(result_channel, f())
        put!(task_channel, inner_task)
        # place the timeout watcher in the same thread as preocessing task (inter-thread interrupts crash julia)
        @async take!(abort_channel) && killtask(inner_task)
    catch e
        # in case that killtimer has not yet kicked in, place the error in the result channel
        isempty(result_channel) && put!(result_channel, e)
    end

    timer = _killtimer(interval, abort_channel, result_channel, failed)
    result = take!(result_channel)

    close(timer)
    isempty(abort_channel) && put!(abort_channel, false) # make sure the abort watcher task ends
    isempty(task_channel) || istaskdone(take!(task_channel)) || @warn("Could not kill task!")

    result isa Exception && rethrow(result)
    
    convert(T, result)
end

macro timeout(interval, expr_to_run, expr_when_fails = nothing, T = Any)
    :(timeout(() -> $(esc(expr_to_run)), $(esc(interval)), $(esc(T)), failed = () -> $(esc(expr_when_fails))))
end

end # module TimeOut