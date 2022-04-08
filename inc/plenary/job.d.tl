local record Job
    command: string
    args: {string}
    cwd: string
    enable_recording: boolean -- TODO: From the plenary source code there is no 'enable_recording' only 'enabled_recording'!
    env: {string:any} -- NOTE: This may be also an array!

    new: function(self: Job, o: Job): Job
    sync: function(self: Job, timeout: integer, wait_interval: integer): Job
    start: function(self: Job)
    stderr_result: function(self: Job): {string}
    result: function(self: Job): {string}

    on_exit: function(self: Job, code: number, signal: number)
end

return Job
