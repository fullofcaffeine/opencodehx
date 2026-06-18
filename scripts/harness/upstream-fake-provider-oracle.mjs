#!/usr/bin/env node
const provider = {
  id: "openai",
  modelID: "gpt-5.2",
  source: "config",
};

const prompt = "Say hello from the fixture.";
const reply = "Hello from the fake provider.";

const transcript = {
  provider,
  request: {
    sessionID: "ses_fake_one",
    prompt,
    system: ["You are a deterministic fixture provider."],
    tools: ["read", "write", "edit", "apply_patch"],
  },
  events: [{ type: "start" }, { type: "text-delta", text: reply }, { type: "finish", reason: "stop" }],
  messages: [
    {
      info: {
        id: "msg_user_one",
        sessionID: "ses_fake_one",
        role: "user",
        time: { created: 1000 },
        format: { type: "text" },
        agent: "fixture",
        model: { providerID: "openai", modelID: "gpt-5.2" },
        tools: { read: true, write: true, edit: true, apply_patch: true },
      },
      parts: [
        {
          id: "prt_user_text",
          sessionID: "ses_fake_one",
          messageID: "msg_user_one",
          type: "text",
          text: prompt,
          time: { start: 1000, end: 1000 },
        },
      ],
    },
    {
      info: {
        id: "msg_assistant_one",
        sessionID: "ses_fake_one",
        role: "assistant",
        time: { created: 1001, completed: 1002 },
        parentID: "msg_user_one",
        modelID: "gpt-5.2",
        providerID: "openai",
        mode: "primary",
        agent: "fixture",
        path: {
          cwd: "/workspace/opencodehx-fixture",
          root: "/workspace/opencodehx-fixture",
        },
        cost: 0,
        tokens: {
          total: 12,
          input: 7,
          output: 5,
          reasoning: 0,
          cache: { read: 0, write: 0 },
        },
        finish: "stop",
      },
      parts: [
        {
          id: "prt_assistant_text",
          sessionID: "ses_fake_one",
          messageID: "msg_assistant_one",
          type: "text",
          text: reply,
          time: { start: 1001, end: 1002 },
        },
      ],
    },
  ],
};

process.stdout.write(`${JSON.stringify(transcript, null, 2)}\n`);
