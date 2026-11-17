# Automation tasks

The current product uses the official webpage's automation tasks, not a separate Bot or group-chat manager. The connected DeepSeek harness engine stores, times and delivers tasks; the phone shell does not substitute Android alarms.

## Create a task

1. Tap the whale, open Automation tasks in the sidebar, and choose New.
2. Enter a task name and complete instructions.
3. Set its run time, repeat pattern and time zone, checking the next scheduled time. Do not rely on wording such as “tomorrow morning” without checking the page's resolved date and zone.
4. Select the offered destination: create one conversation and reuse it, or create a new conversation each time. An existing task may show its currently linked conversation. Check the workspace or directory if applicable.
5. Save, then verify status, instructions, next time and target in the list. On error, retain the draft and resolve the problem; tapping Save does not establish success.

You can also explicitly request a scheduled task in an ordinary conversation, then verify it on the task page. Confirmations, tools and permissions follow the current official engine's actual response; the old patched engine's special confirmation flow is not part of this guide.

## Execution conditions

The owning engine must be running, with its model, network, tools and file permissions available. Phone tasks depend on Android background conditions; computer tasks depend on that computer's service. A phone going offline or closing the app differs from the computer engine stopping.

The task detail defines the time zone and repeat rule. Missed occurrences, minimum intervals and behavior during existing execution are controlled by the official engine. This guide does not promise replay of every occurrence missed during downtime.

## Inspect, pause and run now

Open details to inspect delivery records and the linked conversation. Pause to stop later triggers, and check the next time before resuming. Run now is available only when the page allows it; queued/executing work or interval limits may disable it temporarily.

After pausing, check the linked conversation for work already started or queued. Pausing does not undo file changes.

## Delete a task

Choose Delete in the task detail's More menu and read the confirmation. Official deletion stops future triggers and removes the task and saved delivery records. The original conversation and messages remain; queued messages are not withdrawn. States such as active execution may restrict deletion; follow the page.

Tasks belong to their current engine and do not migrate when you select another computer. See [Settings](10-settings.md) for destinations and [System permissions](04-permissions.md) for background access.
