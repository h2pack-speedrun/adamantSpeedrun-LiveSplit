local actions = {}

function actions.build(controller)
    return {
        recordingStart = controller.startRecording,
        recordingStop = controller.stopRecording,
        recordingClear = controller.clearRecording,
    }
end

function actions.attach(module, controller)
    module.actions.define(actions.build(controller))
end

return actions
