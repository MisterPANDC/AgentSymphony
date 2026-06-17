import { useEffect, useMemo, useRef, useState, type FormEvent, type KeyboardEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Bot,
  ArrowUp,
  Check,
  Code2,
  Copy,
  GitBranch,
  MessageCircle,
  MessageSquare,
  PanelLeft,
  Pencil,
  Plus,
  Recycle,
  RefreshCcw,
  Sparkles,
  Trash2,
  WandSparkles,
  X,
  type LucideIcon
} from "lucide-react";
import { getAiChat, resetAiChat, resolveAiChatApproval, sendAiChatMessage, type AiChatEventDTO } from "../../api/aiChat";
import { reduceCodexEvents, type ApprovalDecision, type CodexRenderPart } from "../../codex";
import { CodexMessageRenderer } from "./CodexMessageRenderer";

type ChatMessage =
  | { id: string; role: "user"; text: string; insertedAt: string }
  | { id: string; role: "assistant"; parts: CodexRenderPart[]; status: string };

const codexEventTypes = new Set([
  "session_started",
  "turn_completed",
  "turn_failed",
  "turn_cancelled",
  "turn_ended_with_error",
  "turn_input_required",
  "approval_required",
  "approval_resolved",
  "approval_auto_approved",
  "notification",
  "other_message",
  "malformed",
  "tool_call_completed",
  "tool_call_failed",
  "unsupported_tool_call",
  "error"
]);

const userEventText = (event: AiChatEventDTO) => {
  const payload = event.payload;
  if (payload && typeof payload === "object" && "text" in payload && typeof payload.text === "string") return payload.text;
  return "";
};

const errorEventToCodex = (event: AiChatEventDTO) => {
  const payload = event.payload;
  const message =
    payload && typeof payload === "object" && "message" in payload && typeof payload.message === "string"
      ? payload.message
      : "Codex chat failed.";
  return { method: "error", params: { message }, id: event.id };
};

const partsToCopyText = (parts: readonly CodexRenderPart[]) =>
  parts
    .map((part) => {
      switch (part.type) {
        case "text":
          return part.text;
        case "reasoning":
          return part.summary ? `Reasoning:\n${part.summary}` : "";
        case "plan":
          return part.steps.map((step) => `- ${typeof step === "string" ? step : JSON.stringify(step)}`).join("\n");
        case "command":
          return [`$ ${part.command}`, part.output].filter(Boolean).join("\n");
        case "fileChange":
          return part.diff ?? "";
        case "toolCall":
          return part.name ? `Tool call: ${part.name}` : "Tool call";
        case "webSearch":
          return part.query ? `Web search: ${part.query}` : "Web search";
        case "imageView":
          return part.path ? `Image viewed: ${part.path}` : "Image viewed";
        case "error":
          return `Error: ${part.message}`;
        case "approval":
          return `Approval required: ${part.requestId}`;
        case "unknown":
          return `Unknown Codex event: ${part.method ?? part.id}`;
      }
    })
    .filter(Boolean)
    .join("\n\n");

type SuggestionIconId = "sparkles" | "code" | "branch" | "wand" | "message" | "bot";

interface SuggestionPrompt {
  id: string;
  label: string;
  icon: SuggestionIconId;
  prompt: string;
}

interface TrashPreviewEntry {
  id: string;
  title: string;
  timestamp: string;
  messageCount: number;
  lastUserPrompt: string;
  messages: ChatMessage[];
}

const suggestionStorageKey = "symphony.aiChat.suggestions";
const legacySuggestionStorageKey = "symphony.aiChat.customSuggestions";
const suggestionIconIds: SuggestionIconId[] = ["sparkles", "code", "branch", "wand", "message", "bot"];

const suggestionIcons: Record<SuggestionIconId, LucideIcon> = {
  sparkles: Sparkles,
  code: Code2,
  branch: GitBranch,
  wand: WandSparkles,
  message: MessageSquare,
  bot: Bot
};

const suggestionIconOptions: Array<{ id: SuggestionIconId; label: string }> = [
  { id: "sparkles", label: "Sparkles" },
  { id: "code", label: "Code" },
  { id: "branch", label: "Branch" },
  { id: "wand", label: "Wand" },
  { id: "message", label: "Message" },
  { id: "bot", label: "Bot" }
];

const seededSuggestionPrompts: SuggestionPrompt[] = [
  { id: "summary", label: "Summarize this project", icon: "sparkles", prompt: "Summarize the current project state and highlight what needs attention." },
  { id: "risky-code", label: "Find risky code paths", icon: "code", prompt: "Review the current codebase for likely bugs or risky implementation details." },
  { id: "next-change", label: "Plan next change", icon: "branch", prompt: "Help me plan the next implementation step for this project." },
  { id: "improve-ux", label: "Improve UX", icon: "wand", prompt: "Suggest focused UI/UX improvements that fit Symphony's current design language." }
];

const isSuggestionIconId = (value: unknown): value is SuggestionIconId =>
  typeof value === "string" && suggestionIconIds.includes(value as SuggestionIconId);

const parseSuggestionPrompts = (value: unknown, fallbackIdPrefix: string): SuggestionPrompt[] => {
  if (!Array.isArray(value)) return [];

  return value.flatMap((item, index) => {
    if (!item || typeof item !== "object") return [];

    const record = item as Record<string, unknown>;
    const label = typeof record.label === "string" ? record.label.trim() : "";
    const prompt = typeof record.prompt === "string" ? record.prompt.trim() : "";
    const icon = isSuggestionIconId(record.icon) ? record.icon : "sparkles";
    const id = typeof record.id === "string" && record.id.trim() ? record.id : `${fallbackIdPrefix}-${index}`;

    if (!label || !prompt) return [];

    return [{ id, label, prompt, icon }];
  });
};

const readSuggestionPrompts = (): SuggestionPrompt[] => {
  if (typeof window === "undefined") return seededSuggestionPrompts;

  try {
    const storedSuggestions = window.localStorage.getItem(suggestionStorageKey);
    if (storedSuggestions !== null) return parseSuggestionPrompts(JSON.parse(storedSuggestions), "prompt");

    const legacySuggestions = parseSuggestionPrompts(JSON.parse(window.localStorage.getItem(legacySuggestionStorageKey) ?? "[]"), "legacy-prompt");
    return [...seededSuggestionPrompts, ...legacySuggestions];
  } catch {
    return seededSuggestionPrompts;
  }
};

const compactChatText = (text: string, fallback: string, maxLength: number) => {
  const compact = text.replace(/\s+/g, " ").trim();
  if (!compact) return fallback;
  return compact.length > maxLength ? `${compact.slice(0, maxLength - 1)}...` : compact;
};

const formatChatTime = (value: string) => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Recent";

  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
};

function buildMessages(events: AiChatEventDTO[], status: string): ChatMessage[] {
  const messages: ChatMessage[] = [];
  let codexBuffer: AiChatEventDTO[] = [];

  const flushCodex = () => {
    if (!codexBuffer.length) return;
    const state = reduceCodexEvents(codexBuffer.map((event) => (event.type === "error" ? errorEventToCodex(event) : event)));
    if (state.parts.length || state.status === "inProgress") {
      messages.push({ id: `assistant-${codexBuffer[0].id}`, role: "assistant", parts: state.parts, status: state.status });
    }
    codexBuffer = [];
  };

  events.forEach((event) => {
    if (event.type === "user_message") {
      flushCodex();
      messages.push({ id: event.id, role: "user", text: userEventText(event), insertedAt: event.insertedAt });
    } else if (codexEventTypes.has(event.type)) {
      codexBuffer.push(event);
    }
  });

  flushCodex();

  if (!messages.length && status === "running") {
    messages.push({ id: "assistant-running", role: "assistant", parts: [], status: "inProgress" });
  }

  return messages;
}

export function AiChatFloatingPanel() {
  const [open, setOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [draft, setDraft] = useState("");
  const [suggestions, setSuggestions] = useState<SuggestionPrompt[]>(readSuggestionPrompts);
  const [trashOpen, setTrashOpen] = useState(false);
  const [selectedTrashPreviewId, setSelectedTrashPreviewId] = useState<string | null>(null);
  const [suggestionEditorOpen, setSuggestionEditorOpen] = useState(false);
  const [editingSuggestionId, setEditingSuggestionId] = useState<string | null>(null);
  const [suggestionDraft, setSuggestionDraft] = useState<{ label: string; prompt: string; icon: SuggestionIconId }>({
    label: "",
    prompt: "",
    icon: "sparkles"
  });
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const composerInputRef = useRef<HTMLTextAreaElement | null>(null);
  const queryClient = useQueryClient();
  const chat = useQuery({
    queryKey: ["ai-chat"],
    queryFn: getAiChat,
    enabled: open,
    refetchInterval: (query) => (query.state.data?.chat.status === "running" ? 1_500 : 5_000)
  });

  const sendMutation = useMutation({
    mutationFn: sendAiChatMessage,
    onSuccess: (data) => {
      setDraft("");
      queryClient.setQueryData(["ai-chat"], data);
    }
  });

  const resetMutation = useMutation({
    mutationFn: resetAiChat,
    onSuccess: () => {
      setDraft("");
      queryClient.invalidateQueries({ queryKey: ["ai-chat"] });
    }
  });

  const approvalMutation = useMutation({
    mutationFn: ({ requestId, decision }: { requestId: string; decision: ApprovalDecision }) => resolveAiChatApproval(requestId, decision),
    onSuccess: (data) => queryClient.setQueryData(["ai-chat"], data)
  });

  const chatData = chat.data?.chat;
  const messages = useMemo(() => buildMessages(chatData?.events ?? [], chatData?.status ?? "idle"), [chatData?.events, chatData?.status]);
  const isRunning = chatData?.status === "running";
  const statusLabel = isRunning ? "running" : chatData?.status === "failed" ? "failed" : null;
  const hasMessages = messages.length > 0;
  const latestUserMessage = [...messages].reverse().find((message): message is Extract<ChatMessage, { role: "user" }> => message.role === "user");
  const threadTitle = latestUserMessage?.text.trim() || "New chat";
  const threadSubtitle = `${messages.length} message${messages.length === 1 ? "" : "s"}`;
  const trashPreviewEntries = useMemo<TrashPreviewEntry[]>(() => {
    const entries: TrashPreviewEntry[] = [];
    let currentEntry: TrashPreviewEntry | null = null;

    messages.forEach((message) => {
      if (message.role === "user") {
        currentEntry = {
          id: `trash-preview-${message.id}`,
          title: compactChatText(message.text, "Chat item", 72),
          timestamp: message.insertedAt,
          messageCount: 1,
          lastUserPrompt: message.text,
          messages: [message]
        };
        entries.push(currentEntry);
        return;
      }

      if (currentEntry) {
        currentEntry.messages.push(message);
        currentEntry.messageCount += 1;
      }
    });

    return entries.slice(-4).reverse();
  }, [messages]);
  const selectedTrashPreview = useMemo(
    () => trashPreviewEntries.find((entry) => entry.id === selectedTrashPreviewId) ?? trashPreviewEntries[0] ?? null,
    [selectedTrashPreviewId, trashPreviewEntries]
  );

  useEffect(() => {
    if (open && viewportRef.current) {
      viewportRef.current.scrollTop = viewportRef.current.scrollHeight;
    }
  }, [messages.length, open]);

  useEffect(() => {
    try {
      window.localStorage.setItem(suggestionStorageKey, JSON.stringify(suggestions.map(({ id, label, prompt, icon }) => ({ id, label, prompt, icon }))));
    } catch {
      // localStorage can be unavailable in restricted browser modes; keep the in-memory state working.
    }
  }, [suggestions]);

  useEffect(() => {
    if (!trashOpen) return;

    const selectedStillExists = selectedTrashPreviewId && trashPreviewEntries.some((entry) => entry.id === selectedTrashPreviewId);
    if (!selectedStillExists) {
      setSelectedTrashPreviewId(trashPreviewEntries[0]?.id ?? null);
    }
  }, [selectedTrashPreviewId, trashOpen, trashPreviewEntries]);

  useEffect(() => {
    if (!open || chat.isLoading || chat.isError || sendMutation.isPending || isRunning) return;

    const frame = window.requestAnimationFrame(() => {
      composerInputRef.current?.focus({ preventScroll: true });
    });

    return () => window.cancelAnimationFrame(frame);
  }, [chat.isError, chat.isLoading, hasMessages, isRunning, open, sendMutation.isPending]);

  const sendText = (text: string) => {
    const message = text.trim();
    if (!message || sendMutation.isPending || isRunning) return;
    sendMutation.mutate(message);
  };

  const submit = (event: FormEvent) => {
    event.preventDefault();
    sendText(draft);
  };

  const handleComposerKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    }
  };

  const fillSuggestionPrompt = (prompt: string) => {
    setDraft(prompt);
    window.requestAnimationFrame(() => {
      const textarea = composerInputRef.current;
      if (!textarea) return;
      textarea.focus({ preventScroll: true });
      textarea.setSelectionRange(prompt.length, prompt.length);
    });
  };

  const resetSuggestionDraft = () => {
    setSuggestionDraft({ label: "", prompt: "", icon: "sparkles" });
  };

  const closeSuggestionEditor = () => {
    setSuggestionEditorOpen(false);
    setEditingSuggestionId(null);
    resetSuggestionDraft();
  };

  const openNewSuggestionEditor = () => {
    setEditingSuggestionId(null);
    resetSuggestionDraft();
    setSuggestionEditorOpen(true);
  };

  const editSuggestionPrompt = (suggestion: SuggestionPrompt) => {
    setEditingSuggestionId(suggestion.id);
    setSuggestionDraft({ label: suggestion.label, prompt: suggestion.prompt, icon: suggestion.icon });
    setSuggestionEditorOpen(true);
  };

  const saveSuggestionPrompt = (event: FormEvent) => {
    event.preventDefault();

    const label = suggestionDraft.label.trim();
    const prompt = suggestionDraft.prompt.trim();

    if (!label || !prompt) return;

    if (editingSuggestionId) {
      setSuggestions((currentSuggestions) =>
        currentSuggestions.map((suggestion) =>
          suggestion.id === editingSuggestionId ? { ...suggestion, label, prompt, icon: suggestionDraft.icon } : suggestion
        )
      );
    } else {
      setSuggestions((currentSuggestions) => [
        ...currentSuggestions,
        {
          id: `custom-${Date.now().toString(36)}-${currentSuggestions.length}`,
          label,
          prompt,
          icon: suggestionDraft.icon
        }
      ]);
    }

    closeSuggestionEditor();
  };

  const removeSuggestionPrompt = (suggestionId: string) => {
    setSuggestions((currentSuggestions) => currentSuggestions.filter((suggestion) => suggestion.id !== suggestionId));
    if (editingSuggestionId === suggestionId) closeSuggestionEditor();
  };

  const trashPreviewTranscript = (entry: TrashPreviewEntry) =>
    entry.messages
      .map((message) => {
        if (message.role === "user") return `User:\n${message.text}`;
        const assistantText = partsToCopyText(message.parts);
        return `Codex:\n${assistantText || message.status}`;
      })
      .join("\n\n");

  const copyTrashPreview = (entry: TrashPreviewEntry) => {
    void navigator.clipboard.writeText(trashPreviewTranscript(entry));
  };

  const copyLastAssistant = () => {
    const assistant = [...messages].reverse().find((message): message is Extract<ChatMessage, { role: "assistant" }> => message.role === "assistant");
    if (assistant) void navigator.clipboard.writeText(partsToCopyText(assistant.parts));
  };

  const composer = (variant: "hero" | "dock") => (
    <form className={`ai-chat-composer ${variant}`} onSubmit={submit}>
      <textarea
        ref={composerInputRef}
        value={draft}
        rows={variant === "hero" ? 3 : 2}
        placeholder={isRunning ? "Codex is responding..." : "Message Codex..."}
        disabled={sendMutation.isPending || isRunning}
        onChange={(event) => setDraft(event.target.value)}
        onKeyDown={handleComposerKeyDown}
      />
      <div className="ai-chat-composer-footer">
        <div className="ai-chat-model-pill">
          <Bot size={14} />
          <span>Codex</span>
        </div>
        <button type="submit" disabled={!draft.trim() || sendMutation.isPending || isRunning} aria-label="Send message">
          {sendMutation.isPending ? <RefreshCcw size={16} /> : <ArrowUp size={17} />}
        </button>
      </div>
    </form>
  );

  if (!open) {
    return (
      <button className="ai-chat-fab" type="button" aria-label="Open AI chat" onClick={() => setOpen(true)}>
        <MessageCircle size={22} />
      </button>
    );
  }

  return (
    <>
      <div className="ai-chat-backdrop" aria-hidden="true" />
      <section className={`ai-chat-panel${historyOpen ? "" : " history-collapsed"}`} aria-label="AI chat">
        <button
          type="button"
          className={`ai-chat-history-toggle${historyOpen ? " open" : ""}`}
          title="Toggle chat history"
          aria-expanded={historyOpen}
          onClick={() => setHistoryOpen((value) => !value)}
        >
          <PanelLeft size={16} />
        </button>
        <aside className="ai-chat-history" aria-label="Chat history">
          <div className="ai-chat-history-inner">
            <div className="ai-chat-history-topbar">
              <button type="button" className="ai-chat-new-thread" onClick={() => resetMutation.mutate()} disabled={resetMutation.isPending || isRunning}>
                <Plus size={16} />
                <span>New Chat</span>
              </button>
              <button
                type="button"
                className={`ai-chat-trash-trigger${trashPreviewEntries.length ? " has-items" : ""}`}
                aria-label={`Open recycle bin${trashPreviewEntries.length ? `, ${trashPreviewEntries.length} item${trashPreviewEntries.length === 1 ? "" : "s"}` : ""}`}
                title="Recycle Bin"
                onClick={() => {
                  setSuggestionEditorOpen(false);
                  setTrashOpen(true);
                }}
              >
                <Recycle size={15} />
                {trashPreviewEntries.length ? <span aria-hidden="true" /> : null}
              </button>
            </div>
            <div className="ai-chat-history-section">
              <div className="ai-chat-history-label">Chats</div>
              {hasMessages ? (
                <div className="ai-chat-thread active">
                  <MessageSquare size={15} />
                  <span>
                    <strong>{threadTitle}</strong>
                    <small>{threadSubtitle}</small>
                  </span>
                </div>
              ) : (
                <div className="ai-chat-history-empty">Chats will appear here after you send a message.</div>
              )}
            </div>
            {chatData?.workspace ? (
              <div className="ai-chat-history-workspace">
                <span>Workspace</span>
                <code>{chatData.workspace}</code>
              </div>
            ) : null}
          </div>
        </aside>

        <main className="ai-chat-main">
          <header className="ai-chat-header">
            <div className="ai-chat-header-left">
              <div className="ai-chat-title">
                <span>New Chat</span>
                {statusLabel ? <span className={`ai-chat-status ${statusLabel}`}>{statusLabel}</span> : null}
              </div>
            </div>
            <div className="ai-chat-actions">
              <button type="button" title="Copy latest assistant message" onClick={copyLastAssistant} disabled={!messages.some((message) => message.role === "assistant")}>
                <Copy size={15} />
              </button>
              <button type="button" title="Close" onClick={() => setOpen(false)}>
                <X size={16} />
              </button>
            </div>
          </header>

          {chat.isLoading ? (
            <div className="ai-chat-viewport empty" ref={viewportRef}>
              <div className="ai-chat-empty">Loading AI chat...</div>
            </div>
          ) : chat.isError ? (
            <div className="ai-chat-viewport empty" ref={viewportRef}>
              <div className="ai-chat-empty error">{chat.error.message}</div>
            </div>
          ) : hasMessages ? (
            <>
              <div className="ai-chat-viewport" ref={viewportRef}>
                {messages.map((message) =>
                  message.role === "user" ? (
                    <div className="ai-chat-row user" key={message.id}>
                      <div className="ai-chat-bubble user">{message.text}</div>
                    </div>
                  ) : (
                    <div className="ai-chat-row assistant" key={message.id}>
                      <div className="ai-chat-bubble assistant">
                        <CodexMessageRenderer
                          parts={message.parts}
                          status={message.status}
                          onResolveApproval={(requestId, decision) => approvalMutation.mutateAsync({ requestId, decision }).then(() => undefined)}
                        />
                      </div>
                    </div>
                  )
                )}
              </div>
              {sendMutation.isError ? <div className="ai-chat-submit-error">{sendMutation.error.message}</div> : null}
              {composer("dock")}
            </>
          ) : (
            <div className="ai-chat-start" ref={viewportRef}>
              <div className="ai-chat-start-inner">
                <div className="ai-chat-start-mark">
                  <Bot size={22} />
                </div>
                <h2>How can I help with Symphony?</h2>
                <p>Ask Codex to inspect the project, explain behavior, plan changes, or review implementation details.</p>
                {composer("hero")}
                <div className="ai-chat-suggestion-area">
                  <div className="ai-chat-suggestions">
                    {suggestions.map((suggestion) => {
                      const Icon = suggestionIcons[suggestion.icon];
                      return (
                        <div className="ai-chat-suggestion-item" key={suggestion.id}>
                          <button
                            type="button"
                            className="ai-chat-suggestion-button"
                            onClick={() => fillSuggestionPrompt(suggestion.prompt)}
                            disabled={sendMutation.isPending || isRunning}
                          >
                            <Icon size={16} />
                            <span>{suggestion.label}</span>
                          </button>
                          <button
                            type="button"
                            className="ai-chat-suggestion-remove"
                            title={`Remove ${suggestion.label}`}
                            aria-label={`Remove ${suggestion.label}`}
                            onClick={() => removeSuggestionPrompt(suggestion.id)}
                          >
                            <Trash2 size={12} />
                          </button>
                          <button
                            type="button"
                            className="ai-chat-suggestion-edit"
                            title={`Edit ${suggestion.label}`}
                            aria-label={`Edit ${suggestion.label}`}
                            onClick={() => editSuggestionPrompt(suggestion)}
                          >
                            <Pencil size={12} />
                          </button>
                        </div>
                      );
                    })}
                    <button
                      type="button"
                      className="ai-chat-suggestion-add"
                      aria-label="Add prompt"
                      aria-expanded={suggestionEditorOpen}
                      title="Add prompt"
                      onClick={() => {
                        if (suggestionEditorOpen && !editingSuggestionId) {
                          closeSuggestionEditor();
                        } else {
                          openNewSuggestionEditor();
                        }
                      }}
                      disabled={sendMutation.isPending || isRunning}
                    >
                      <Plus size={15} />
                    </button>
                  </div>
                </div>
                {sendMutation.isError ? <div className="ai-chat-submit-error inline">{sendMutation.error.message}</div> : null}
              </div>
            </div>
          )}
        </main>
        {suggestionEditorOpen ? (
          <div className="ai-chat-prompt-dialog-layer" role="presentation">
            <form
              className="ai-chat-suggestion-editor"
              onSubmit={saveSuggestionPrompt}
              role="dialog"
              aria-modal="true"
              aria-label={editingSuggestionId ? "Edit prompt" : "New prompt"}
            >
              <div className="ai-chat-suggestion-editor-header">
                <strong>{editingSuggestionId ? "Edit prompt" : "New prompt"}</strong>
                <button type="button" aria-label="Close prompt editor" onClick={closeSuggestionEditor}>
                  <X size={14} />
                </button>
              </div>
              <div className="ai-chat-suggestion-editor-grid">
                <label>
                  <span>Name</span>
                  <input
                    value={suggestionDraft.label}
                    maxLength={42}
                    placeholder="Review setup"
                    aria-label="Suggestion label"
                    autoFocus
                    autoComplete="off"
                    onChange={(event) => setSuggestionDraft((currentDraft) => ({ ...currentDraft, label: event.target.value }))}
                  />
                </label>
                <label>
                  <span>Prompt</span>
                  <textarea
                    value={suggestionDraft.prompt}
                    rows={3}
                    placeholder="Inspect the current implementation and call out the next practical step."
                    aria-label="Suggestion prompt"
                    onChange={(event) => setSuggestionDraft((currentDraft) => ({ ...currentDraft, prompt: event.target.value }))}
                  />
                </label>
              </div>
              <div className="ai-chat-suggestion-editor-footer">
                <div className="ai-chat-suggestion-icon-options" aria-label="Prompt icon">
                  {suggestionIconOptions.map((option) => {
                    const Icon = suggestionIcons[option.id];
                    const selected = suggestionDraft.icon === option.id;
                    return (
                      <button
                        type="button"
                        key={option.id}
                        className={selected ? "selected" : ""}
                        aria-label={`${option.label} icon`}
                        aria-pressed={selected}
                        title={option.label}
                        onClick={() => setSuggestionDraft((currentDraft) => ({ ...currentDraft, icon: option.id }))}
                      >
                        <Icon size={15} />
                      </button>
                    );
                  })}
                </div>
                <button type="submit" aria-label="Save prompt" disabled={!suggestionDraft.label.trim() || !suggestionDraft.prompt.trim()}>
                  <Check size={14} />
                  <span>Save</span>
                </button>
              </div>
            </form>
          </div>
        ) : null}
        {trashOpen ? (
          <div className="ai-chat-trash-dialog-layer" role="presentation">
            <section className="ai-chat-trash-dialog" role="dialog" aria-modal="true" aria-label="Recycle Bin">
              <header className="ai-chat-trash-dialog-header">
                <div>
                  <strong>Recycle Bin</strong>
                  <span>{trashPreviewEntries.length ? `${trashPreviewEntries.length} recent item${trashPreviewEntries.length === 1 ? "" : "s"}` : "No items yet"}</span>
                </div>
                <button type="button" aria-label="Close recycle bin" onClick={() => setTrashOpen(false)}>
                  <X size={14} />
                </button>
              </header>

              {trashPreviewEntries.length && selectedTrashPreview ? (
                <div className="ai-chat-trash-content">
                  <div className="ai-chat-trash-list" aria-label="Recycle bin items">
                    {trashPreviewEntries.map((entry) => (
                      <button
                        type="button"
                        key={entry.id}
                        className={`ai-chat-trash-item${selectedTrashPreview.id === entry.id ? " selected" : ""}`}
                        onClick={() => setSelectedTrashPreviewId(entry.id)}
                      >
                        <MessageSquare size={14} />
                        <span>
                          <strong>{entry.title}</strong>
                          <small>{formatChatTime(entry.timestamp)}</small>
                        </span>
                      </button>
                    ))}
                  </div>
                  <div className="ai-chat-trash-preview">
                    <div className="ai-chat-trash-preview-header">
                      <strong>{selectedTrashPreview.title}</strong>
                      <span>
                        {formatChatTime(selectedTrashPreview.timestamp)} · {selectedTrashPreview.messageCount} messages
                      </span>
                    </div>
                    <div className="ai-chat-transcript-preview">
                      {selectedTrashPreview.messages.length ? (
                        selectedTrashPreview.messages.map((message) => {
                          const messageText = message.role === "user" ? message.text : partsToCopyText(message.parts) || message.status;
                          return (
                            <article className={`ai-chat-trash-message ${message.role}`} key={message.id}>
                              <span>{message.role === "user" ? "You" : "Codex"}</span>
                              <p>{messageText}</p>
                            </article>
                          );
                        })
                      ) : (
                        <div className="ai-chat-trash-preview-empty">No conversation content is available for this item.</div>
                      )}
                    </div>
                    <div className="ai-chat-trash-preview-actions">
                      <div>
                        <button type="button" onClick={() => copyTrashPreview(selectedTrashPreview)}>
                          Copy item
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              ) : (
                <div className="ai-chat-trash-empty">
                  <Recycle size={20} />
                  <strong>Nothing here yet</strong>
                  <span>Items from your chat history will appear here when available.</span>
                </div>
              )}
            </section>
          </div>
        ) : null}
      </section>
    </>
  );
}
