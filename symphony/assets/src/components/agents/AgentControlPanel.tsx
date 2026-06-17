import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, CheckCircle2, FileText, KeyRound, Plus, RefreshCcw, Search, Server, Terminal, Upload, X } from "lucide-react";
import { listAgents, refreshAgentUsage, registerAgent, saveAgentMcpRegistry } from "../../api/agents";
import type { AgentAuthMode, AgentMcpRegistryDTO, AgentMcpServerDTO, AvailableAgentDTO, CodexRateLimitBucketDTO, RegisteredAgentDTO } from "../../types/agent";

const fallbackAgents: AvailableAgentDTO[] = [
  {
    provider: "codex",
    label: "Codex",
    description: "OpenAI Codex CLI agent",
    modes: ["subscription", "api", "auth_json"]
  }
];

const MCP_JSON_PLACEHOLDER = `{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"],
      "env": {},
      "startup_timeout_sec": 15
    }
  }
}`;

export function AgentControlPanel() {
  const queryClient = useQueryClient();
  const agents = useQuery({ queryKey: ["agents"], queryFn: listAgents, retry: false });
  const [dialogOpen, setDialogOpen] = useState(false);
  const [mcpDialogOpen, setMcpDialogOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [selectedProvider, setSelectedProvider] = useState<"codex">("codex");
  const [agentName, setAgentName] = useState("");
  const [authMode, setAuthMode] = useState<AgentAuthMode>("subscription");
  const [apiKey, setApiKey] = useState("");
  const [authJson, setAuthJson] = useState("");
  const [authJsonName, setAuthJsonName] = useState("");
  const [selectedMcpServerNames, setSelectedMcpServerNames] = useState<string[]>([]);

  const availableAgents = agents.data?.availableAgents ?? fallbackAgents;
  const filteredAgents = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return availableAgents;
    return availableAgents.filter((agent) => `${agent.label} ${agent.description}`.toLowerCase().includes(needle));
  }, [availableAgents, query]);

  const register = useMutation({
    mutationFn: registerAgent,
    onSuccess: () => {
      setDialogOpen(false);
      setQuery("");
      setSelectedProvider("codex");
      setAgentName("");
      setAuthMode("subscription");
      setApiKey("");
      setAuthJson("");
      setAuthJsonName("");
      setSelectedMcpServerNames([]);
      queryClient.invalidateQueries({ queryKey: ["agents"] });
      window.setTimeout(() => queryClient.invalidateQueries({ queryKey: ["agents"] }), 1500);
    }
  });

  const refreshUsage = useMutation({
    mutationFn: refreshAgentUsage,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["agents"] })
  });

  function submitRegistration(event: FormEvent) {
    event.preventDefault();
    register.mutate({
      provider: selectedProvider,
      name: agentName || undefined,
      authMode,
      apiKey: authMode === "api" ? apiKey : undefined,
      authJson: authMode === "auth_json" ? authJson : undefined,
      mcpServerNames: selectedMcpServerNames
    });
  }

  async function loadAuthJsonFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setAuthJson(await file.text());
    setAuthJsonName(file.name);
  }

  const registerDisabled =
    register.isPending ||
    (authMode === "api" && !apiKey.trim()) ||
    (authMode === "auth_json" && !authJson.trim());
  const mcpRegistry = agents.data?.mcp ?? { path: "", mcpServers: {} };
  const mcpServerNames = Object.keys(mcpRegistry.mcpServers).sort();

  return (
    <div className="space-y-4">
      <section className="panel">
        <div className="panel-header">
          <h1 className="flex items-center gap-2 text-sm font-semibold"><Bot size={15} /> Agents</h1>
          <div className="flex items-center gap-2">
            <button className="text-button" type="button" onClick={() => setMcpDialogOpen(true)}><Server size={14} /> MCP</button>
            <Dialog.Root open={dialogOpen} onOpenChange={setDialogOpen}>
              <Dialog.Trigger asChild>
                <button className="text-button" type="button"><Plus size={14} /> Register agent</button>
              </Dialog.Trigger>
            <Dialog.Portal>
              <Dialog.Overlay className="fixed inset-0 z-30 bg-black/10" />
              <Dialog.Content className="fixed left-1/2 top-16 z-40 w-[min(720px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl outline-none">
                <Dialog.Title className="sr-only">Register agent</Dialog.Title>
                <form onSubmit={submitRegistration}>
                  <div className="flex items-center gap-2 border-b border-[#eaebef] px-3 py-2">
                    <Search size={16} className="text-[#686b73]" />
                    <input
                      autoFocus
                      className="h-9 min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-[#8a8d96]"
                      placeholder="Search agents"
                      value={query}
                      onChange={(event) => setQuery(event.target.value)}
                    />
                    <Dialog.Close className="dialog-close-button" title="Close agent registration">
                      <X size={15} />
                    </Dialog.Close>
                  </div>
                  <div className="grid gap-3 p-3">
                    <div className="grid gap-1">
                      {filteredAgents.map((agent) => (
                        <button
                          key={agent.provider}
                          className={`flex w-full items-center justify-between gap-4 rounded-md px-3 py-2 text-left transition-colors hover:bg-[#f4f5f7] ${selectedProvider === agent.provider ? "bg-[#f4f5f7]" : ""}`}
                          type="button"
                          onClick={() => setSelectedProvider(agent.provider)}
                        >
                          <span className="flex min-w-0 items-center gap-3">
                            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-[#fbfbfc] text-[#555d68]">
                              <OpenAILogo size={16} />
                            </span>
                            <span className="min-w-0">
                              <span className="block truncate text-sm font-medium">{agent.label}</span>
                              <span className="block truncate text-xs text-[#686b73]">{agent.description}</span>
                            </span>
                          </span>
                          {selectedProvider === agent.provider && <CheckCircle2 size={16} className="shrink-0 text-[#4b5563]" />}
                        </button>
                      ))}
                    </div>

                    <input
                      className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                      placeholder="Agent name"
                      value={agentName}
                      onChange={(event) => setAgentName(event.target.value)}
                      maxLength={80}
                    />

                    <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                      <button
                        className={`rounded-md border px-3 py-2 text-left text-sm ${authMode === "subscription" ? "border-[#9ca3af] bg-[#f4f5f7]" : "border-[#dedfe4] bg-white"}`}
                        type="button"
                        onClick={() => setAuthMode("subscription")}
                      >
                        <span className="flex items-center gap-2 font-medium"><Terminal size={14} /> Subscription</span>
                        <span className="mt-1 block text-xs text-[#686b73]">CODEX_HOME + codex login</span>
                      </button>
                      <button
                        className={`rounded-md border px-3 py-2 text-left text-sm ${authMode === "api" ? "border-[#9ca3af] bg-[#f4f5f7]" : "border-[#dedfe4] bg-white"}`}
                        type="button"
                        onClick={() => setAuthMode("api")}
                      >
                        <span className="flex items-center gap-2 font-medium"><KeyRound size={14} /> API</span>
                        <span className="mt-1 block text-xs text-[#686b73]">CODEX_HOME + api key</span>
                      </button>
                      <button
                        className={`rounded-md border px-3 py-2 text-left text-sm ${authMode === "auth_json" ? "border-[#9ca3af] bg-[#f4f5f7]" : "border-[#dedfe4] bg-white"}`}
                        type="button"
                        onClick={() => setAuthMode("auth_json")}
                      >
                        <span className="flex items-center gap-2 font-medium"><FileText size={14} /> auth.json</span>
                        <span className="mt-1 block text-xs text-[#686b73]">CODEX_HOME/auth.json</span>
                      </button>
                    </div>

                    {authMode === "api" && (
                      <input
                        className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                        type="password"
                        placeholder="OpenAI API key"
                        value={apiKey}
                        onChange={(event) => setApiKey(event.target.value)}
                      />
                    )}

                    {authMode === "auth_json" && (
                      <div className="grid gap-2">
                        <label className="text-button w-fit cursor-pointer" htmlFor="agent-auth-json-file">
                          <Upload size={14} />
                          {authJsonName || "Choose auth.json"}
                          <input
                            id="agent-auth-json-file"
                            className="sr-only"
                            type="file"
                            accept="application/json,.json"
                            onChange={loadAuthJsonFile}
                          />
                        </label>
                        <textarea
                          className="min-h-28 resize-y rounded-md border border-[#dedfe4] bg-white px-3 py-2 text-xs outline-none focus:border-[#9ca3af]"
                          placeholder="{ ... }"
                          value={authJson}
                          onChange={(event) => {
                            setAuthJson(event.target.value);
                            setAuthJsonName("");
                          }}
                        />
                      </div>
                    )}

                    <div className="grid gap-3 rounded-md border border-[#eaebef] bg-[#fbfbfc] p-3">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="flex items-center gap-1.5 text-xs font-semibold text-[#1d1d1f]">
                            <Server size={13} />
                            MCP servers
                          </div>
                          <div className="mono mt-0.5 text-[11px] text-[#686b73]">{mcpRegistry.path || "agent-mcp.json"}</div>
                        </div>
                        <button className="text-button" type="button" onClick={() => setMcpDialogOpen(true)}>
                          <Plus size={14} /> Define server
                        </button>
                      </div>
                      {mcpServerNames.length > 0 ? (
                        <div className="grid gap-1">
                          {mcpServerNames.map((name) => (
                            <label key={name} className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-3 rounded-md border border-[#eaebef] bg-white px-3 py-2.5 text-xs">
                              <span className="grid min-w-0 gap-1">
                                <span className="flex min-w-0 items-center gap-2">
                                  <span className="truncate font-medium text-[#555d68]">{name}</span>
                                  <span className="shrink-0 rounded border border-[#e4e6eb] bg-[#fbfbfc] px-1.5 py-0.5 text-[10px] uppercase text-[#8a8d96]">
                                    Codex MCP
                                  </span>
                                </span>
                                <span className="mono block truncate text-[11px] text-[#686b73]">{mcpCommandPreview(mcpRegistry.mcpServers[name])}</span>
                                <span className="block truncate text-[11px] text-[#8a8d96]">{mcpMetadataSummary(mcpRegistry.mcpServers[name])}</span>
                              </span>
                              <input
                                className="mt-1"
                                type="checkbox"
                                checked={selectedMcpServerNames.includes(name)}
                                onChange={(event) => {
                                  setSelectedMcpServerNames((current) =>
                                    event.target.checked ? [...current, name] : current.filter((item) => item !== name)
                                  );
                                }}
                              />
                            </label>
                          ))}
                        </div>
                      ) : (
                        <div className="rounded-md border border-dashed border-[#dedfe4] bg-white px-3 py-4 text-xs text-[#686b73]">
                          No shared MCP server definitions yet. Define a server first, then select it for this agent.
                        </div>
                      )}
                    </div>

                    {register.isError && <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">{register.error.message}</div>}

                    <div className="flex justify-end gap-2 border-t border-[#eaebef] pt-3">
                      <Dialog.Close className="text-button" type="button">Cancel</Dialog.Close>
                      <button className="text-button" type="submit" disabled={registerDisabled}>
                        <Plus size={14} /> Register
                      </button>
                    </div>
                  </div>
                </form>
              </Dialog.Content>
            </Dialog.Portal>
            </Dialog.Root>
          </div>
        </div>
        <AgentList
          agents={agents.data?.agents ?? []}
          error={agents.isError ? agents.error.message : null}
          loading={agents.isLoading}
          onRefreshUsage={(id) => refreshUsage.mutate(id)}
          refreshingAgentId={refreshUsage.isPending ? refreshUsage.variables : undefined}
        />
      </section>
      <McpManagerDialog
        open={mcpDialogOpen}
        onOpenChange={setMcpDialogOpen}
        registry={mcpRegistry}
        onChanged={() => queryClient.invalidateQueries({ queryKey: ["agents"] })}
      />
    </div>
  );
}

function McpManagerDialog({
  open,
  onOpenChange,
  registry,
  onChanged
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  registry: AgentMcpRegistryDTO;
  onChanged: () => void;
}) {
  const [mcpJson, setMcpJson] = useState("");
  const [error, setError] = useState<string | null>(null);
  const wasOpen = useRef(open);
  const formattedRegistry = useMemo(() => formatMcpRegistry(registry), [registry]);
  const parsedRegistry = useMemo(() => parseMcpRegistryJson(mcpJson), [mcpJson]);
  const saveMcp = useMutation({
    mutationFn: saveAgentMcpRegistry,
    onSuccess: (data) => {
      setMcpJson(formatMcpRegistry(data.mcp));
      setError(null);
      onChanged();
    },
    onError: (error) => setError(error.message)
  });
  const serverNames = Object.keys(registry.mcpServers).sort();
  const inlineParseError = mcpJson.trim() && !parsedRegistry.ok ? parsedRegistry.error : null;
  const submitDisabled = saveMcp.isPending || !mcpJson.trim() || !parsedRegistry.ok;

  useEffect(() => {
    if (open && !wasOpen.current) {
      setMcpJson(serverNames.length > 0 ? formattedRegistry : "");
      setError(null);
    }
    wasOpen.current = open;
  }, [formattedRegistry, open, serverNames.length]);

  function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);

    const registryResult = parseMcpRegistryJson(mcpJson);
    if (!registryResult.ok) {
      setError(registryResult.error);
      return;
    }

    saveMcp.mutate(registryResult.value);
  }

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/10" />
        <Dialog.Content className="fixed left-1/2 top-8 z-50 w-[min(920px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl outline-none">
          <Dialog.Title className="sr-only">MCP servers</Dialog.Title>
          <div className="flex items-center justify-between gap-3 border-b border-[#eaebef] px-4 py-3">
            <div className="flex min-w-0 items-center gap-3">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-[#fbfbfc] text-[#555d68]">
                <Server size={16} />
              </span>
              <div className="min-w-0">
                <div className="text-sm font-semibold">MCP servers</div>
                <div className="mono mt-0.5 truncate text-[11px] text-[#8a8d96]">{registry.path || "agent-mcp.json"}</div>
              </div>
            </div>
            <Dialog.Close className="dialog-close-button" title="Close MCP servers">
              <X size={15} />
            </Dialog.Close>
          </div>
          <div className="grid max-h-[calc(100vh-96px)] gap-3 overflow-auto p-3">
            {registry.error && (
              <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">{registry.error}</div>
            )}

            <div className="grid gap-2">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-xs font-semibold text-[#1d1d1f]">Configured definitions</div>
                  <div className="mt-0.5 text-[11px] text-[#686b73]">Available to select when registering Codex agents.</div>
                </div>
                <span className="rounded-full border border-[#dedfe4] bg-[#fbfbfc] px-2 py-0.5 text-xs text-[#686b73]">{serverNames.length}</span>
              </div>
              {serverNames.length > 0 ? (
                <div className="grid gap-2">
                  {serverNames.map((serverName) => (
                    <McpDefinitionCard key={serverName} name={serverName} server={registry.mcpServers[serverName]} />
                  ))}
                </div>
              ) : (
                <div className="rounded-md border border-dashed border-[#dedfe4] bg-[#fbfbfc] px-3 py-4 text-center text-sm text-[#686b73]">
                  No MCP server definitions yet.
                </div>
              )}
            </div>

            <form className="grid gap-3 border-t border-[#eaebef] pt-3" onSubmit={submit}>
              <div>
                <div className="text-xs font-semibold text-[#1d1d1f]">MCP JSON</div>
                <div className="mt-0.5 text-[11px] text-[#686b73]">Saved as agent-mcp.json. Saving replaces the shared MCP registry.</div>
              </div>

              <textarea
                className={`mono min-h-[280px] resize-y rounded-md border bg-white px-3 py-2 text-xs leading-5 outline-none placeholder:text-[#9ca3af] focus:border-[#9ca3af] ${
                  inlineParseError ? "border-[#e5b7b7]" : "border-[#dedfe4]"
                }`}
                placeholder={MCP_JSON_PLACEHOLDER}
                spellCheck={false}
                value={mcpJson}
                onChange={(event) => {
                  setMcpJson(event.target.value);
                  setError(null);
                }}
              />

              {(inlineParseError || error || saveMcp.isError) && (
                <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">
                  {inlineParseError || error || saveMcp.error?.message}
                </div>
              )}
              <div className="flex justify-end border-t border-[#eaebef] pt-2">
                <button className="text-button" type="submit" disabled={submitDisabled}>
                  <FileText size={14} /> Save
                </button>
              </div>
            </form>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function McpDefinitionCard({ name, server }: { name: string; server?: AgentMcpRegistryDTO["mcpServers"][string] }) {
  return (
    <div className="grid gap-2 rounded-md border border-[#eaebef] bg-[#fbfbfc] px-3 py-2.5">
      <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="truncate text-sm font-medium text-[#1d1d1f]">{name}</div>
          <div className="mt-0.5 truncate text-[11px] text-[#8a8d96]">{mcpMetadataSummary(server)}</div>
        </div>
        <span className="rounded border border-[#dedfe4] bg-white px-1.5 py-0.5 text-[11px] text-[#686b73]">definition</span>
      </div>
      <div className="mono min-w-0 truncate rounded border border-[#eaebef] bg-white px-2 py-1.5 text-xs text-[#555d68]">{mcpCommandPreview(server)}</div>
    </div>
  );
}

type ParsedMcpValue<T> = { ok: true; value: T } | { ok: false; error: string };

function validMcpServerName(name: string) {
  return /^[A-Za-z0-9_.-]+$/.test(name);
}

function formatMcpRegistry(registry: AgentMcpRegistryDTO) {
  const mcpServers = Object.keys(registry.mcpServers)
    .sort()
    .reduce<Record<string, AgentMcpServerDTO>>((acc, name) => {
      acc[name] = normalizeMcpServerForJson(registry.mcpServers[name]);
      return acc;
    }, {});

  return JSON.stringify({ mcpServers }, null, 2);
}

function normalizeMcpServerForJson(server: AgentMcpServerDTO) {
  const normalized: AgentMcpServerDTO = {
    command: server.command,
    args: server.args ?? [],
    env: server.env ?? {}
  };
  const timeout = server.startup_timeout_sec ?? server.startupTimeoutSec;
  if (timeout != null) normalized.startup_timeout_sec = timeout;
  return normalized;
}

function parseMcpRegistryJson(value: string): ParsedMcpValue<{ mcpServers: Record<string, AgentMcpServerDTO> }> {
  const trimmed = value.trim();
  if (!trimmed) return { ok: false, error: "MCP JSON is required." };

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return { ok: false, error: "MCP JSON must be valid JSON." };
  }

  if (!isPlainRecord(parsed)) {
    return { ok: false, error: "MCP JSON must be an object." };
  }

  const mcpServers = parsed.mcpServers;
  if (!isPlainRecord(mcpServers)) {
    return { ok: false, error: "MCP JSON must contain a top-level mcpServers object." };
  }

  const servers: Record<string, AgentMcpServerDTO> = {};
  for (const [name, server] of Object.entries(mcpServers)) {
    const result = normalizeMcpServerInput(name, server);
    if (!result.ok) {
      return { ok: false, error: result.error };
    }
    servers[name] = result.value;
  }

  return { ok: true, value: { mcpServers: servers } };
}

function normalizeMcpServerInput(name: string, server: unknown): ParsedMcpValue<AgentMcpServerDTO> {
  if (!validMcpServerName(name)) {
    return { ok: false, error: `MCP server "${name}" must use letters, numbers, dots, dashes, or underscores.` };
  }

  if (!isPlainRecord(server)) {
    return { ok: false, error: `MCP server "${name}" must be a JSON object.` };
  }

  const command = server.command;
  if (typeof command !== "string" || !command.trim()) {
    return { ok: false, error: `MCP server "${name}" requires a command string.` };
  }

  const args = server.args ?? [];
  if (!Array.isArray(args) || !args.every((item) => typeof item === "string")) {
    return { ok: false, error: `MCP server "${name}" args must be a string array.` };
  }

  const env = server.env ?? {};
  if (!isPlainRecord(env) || !Object.values(env).every((value) => typeof value === "string")) {
    return { ok: false, error: `MCP server "${name}" env must be an object with string values.` };
  }

  const startupTimeout = server.startup_timeout_sec ?? server.startupTimeoutSec;
  if (startupTimeout != null && (typeof startupTimeout !== "number" || !Number.isInteger(startupTimeout) || startupTimeout <= 0)) {
    return { ok: false, error: `MCP server "${name}" startup_timeout_sec must be a positive integer.` };
  }

  const normalized: AgentMcpServerDTO = {
    command: command.trim(),
    args,
    env: Object.entries(env).reduce<Record<string, string>>((acc, [key, value]) => {
      acc[key] = value as string;
      return acc;
    }, {})
  };

  if (startupTimeout != null) normalized.startup_timeout_sec = startupTimeout;
  return { ok: true, value: normalized };
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function mcpCommandPreview(server?: AgentMcpRegistryDTO["mcpServers"][string]) {
  if (!server?.command) return "No command";
  return shellCommandPreview(server.command, server.args ?? []);
}

function shellCommandPreview(command: string, args: string[]) {
  return [command, ...args].map(shellToken).join(" ");
}

function shellToken(value: string) {
  if (/^[A-Za-z0-9_./:=@%+-]+$/.test(value)) return value;
  return JSON.stringify(value);
}

function mcpMetadataSummary(server?: AgentMcpRegistryDTO["mcpServers"][string]) {
  if (!server) return "No server details";
  const args = server.args ?? [];
  const env = server.env ?? {};
  const timeout = server.startupTimeoutSec ?? server.startup_timeout_sec;
  const parts = [
    `${args.length} ${args.length === 1 ? "arg" : "args"}`,
    mcpEnvSummary(env),
    timeout ? `${timeout}s startup timeout` : "default startup timeout"
  ];
  return parts.join(" | ");
}

function mcpEnvSummary(env: Record<string, string>) {
  const keys = Object.keys(env).sort();
  if (keys.length === 0) return "No env";
  return `${keys.length} ${keys.length === 1 ? "env key" : "env keys"}: ${keys.join(", ")}`;
}

function OpenAILogo({ size = 16 }: { size?: number }) {
  return (
    <svg
      aria-hidden="true"
      fill="currentColor"
      fillRule="evenodd"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="M9.205 8.658v-2.26c0-.19.072-.333.238-.428l4.543-2.616c.619-.357 1.356-.523 2.117-.523 2.854 0 4.662 2.212 4.662 4.566 0 .167 0 .357-.024.547l-4.71-2.759a.797.797 0 00-.856 0l-5.97 3.473zm10.609 8.8V12.06c0-.333-.143-.57-.429-.737l-5.97-3.473 1.95-1.118a.433.433 0 01.476 0l4.543 2.617c1.309.76 2.189 2.378 2.189 3.948 0 1.808-1.07 3.473-2.76 4.163zM7.802 12.703l-1.95-1.142c-.167-.095-.239-.238-.239-.428V5.899c0-2.545 1.95-4.472 4.591-4.472 1 0 1.927.333 2.712.928L8.23 5.067c-.285.166-.428.404-.428.737v6.898zM12 15.128l-2.795-1.57v-3.33L12 8.658l2.795 1.57v3.33L12 15.128zm1.796 7.23c-1 0-1.927-.332-2.712-.927l4.686-2.712c.285-.166.428-.404.428-.737v-6.898l1.974 1.142c.167.095.238.238.238.428v5.233c0 2.545-1.974 4.472-4.614 4.472zm-5.637-5.303l-4.544-2.617c-1.308-.761-2.188-2.378-2.188-3.948A4.482 4.482 0 014.21 6.327v5.423c0 .333.143.571.428.738l5.947 3.449-1.95 1.118a.432.432 0 01-.476 0zm-.262 3.9c-2.688 0-4.662-2.021-4.662-4.519 0-.19.024-.38.047-.57l4.686 2.71c.286.167.571.167.856 0l5.97-3.448v2.26c0 .19-.07.333-.237.428l-4.543 2.616c-.619.357-1.356.523-2.117.523zm5.899 2.83a5.947 5.947 0 005.827-4.756C22.287 18.339 24 15.84 24 13.296c0-1.665-.713-3.282-1.998-4.448.119-.5.19-.999.19-1.498 0-3.401-2.759-5.947-5.946-5.947-.642 0-1.26.095-1.88.31A5.962 5.962 0 0010.205 0a5.947 5.947 0 00-5.827 4.757C1.713 5.447 0 7.945 0 10.49c0 1.666.713 3.283 1.998 4.448-.119.5-.19 1-.19 1.499 0 3.401 2.759 5.946 5.946 5.946.642 0 1.26-.095 1.88-.309a5.96 5.96 0 004.162 1.713z" />
    </svg>
  );
}

function AgentList({
  agents,
  error,
  loading,
  onRefreshUsage,
  refreshingAgentId
}: {
  agents: RegisteredAgentDTO[];
  error?: string | null;
  loading: boolean;
  onRefreshUsage: (id: string) => void;
  refreshingAgentId?: string;
}) {
  if (loading) {
    return <div className="px-4 py-8 text-center text-sm text-[#686b73]">Loading agents</div>;
  }

  if (error) {
    return <div className="px-4 py-8 text-center text-sm text-[#9b1c1c]">Agents could not load: {error}</div>;
  }

  if (agents.length === 0) {
    return <div className="px-4 py-10 text-center text-sm text-[#686b73]">No registered agents</div>;
  }

  return (
    <div className="grid gap-3 p-3 lg:grid-cols-2">
      {agents.map((agent) => {
        const unregisteredInstalled = (agent.mcpInstalledServers ?? []).filter((server) => !server.registered);

        return (
          <div key={agent.id} className="grid min-w-0 gap-3 rounded-md border border-[#eaebef] bg-[#fbfbfc] p-3">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2 text-sm font-semibold">
                  <span className="grid h-8 w-8 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-white text-[#555d68]">
                    <OpenAILogo size={16} />
                  </span>
                  {agent.name}
                  <span className="rounded border border-[#dedfe4] bg-white px-1.5 py-0.5 text-[11px] font-medium uppercase text-[#686b73]">{authModeLabel(agent.authMode)}</span>
                </div>
              </div>
              <span className="rounded-full border border-[#dedfe4] bg-white px-2 py-1 text-xs font-medium text-[#555d68]">{statusLabel(agent.credentialStatus)}</span>
            </div>
            <div className="grid gap-1 rounded-md border border-[#eaebef] bg-white px-3 py-2">
              <div className="text-[11px] font-medium uppercase text-[#8a8d96]">Codex home</div>
              <div className="mono truncate text-xs text-[#555d68]">{agent.codexHome}</div>
            </div>
            <div className="grid gap-2 rounded-md border border-[#eaebef] bg-white px-3 py-2 text-xs">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-medium text-[#555d68]">MCP</span>
                <span className="flex min-w-0 items-center gap-2">
                  {(agent.mcpServerNames ?? []).length > 0 && <span className="truncate text-[#8a8d96]">{agent.mcpServerNames.join(", ")}</span>}
                  <span className="rounded-full border border-[#dedfe4] bg-[#fbfbfc] px-2 py-0.5 text-[#686b73]">{mcpStatusLabel(agent.mcpInstallStatus)}</span>
                </span>
              </div>
              {unregisteredInstalled.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {unregisteredInstalled.map((server) => (
                    <span key={server.name} className="rounded border border-[#dedfe4] bg-[#fbfbfc] px-1.5 py-0.5 text-[11px] text-[#686b73]">
                      {server.name} unregistered
                    </span>
                  ))}
                </div>
              )}
            </div>
            {agent.authMode === "subscription" && (
              <SubscriptionUsageCard
                agent={agent}
                onRefresh={() => onRefreshUsage(agent.id)}
                refreshing={refreshingAgentId === agent.id}
              />
            )}
            {agent.lastLoginMessage && agent.credentialStatus === "failed" && (
              <div className="mt-3 rounded-md border border-[#efcaca] bg-white px-3 py-2 text-xs text-[#9b1c1c]">{agent.lastLoginMessage}</div>
            )}
            {agent.mcpInstallMessage && agent.mcpInstallStatus === "failed" && (
              <div className="rounded-md border border-[#efcaca] bg-white px-3 py-2 text-xs text-[#9b1c1c]">{agent.mcpInstallMessage}</div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function SubscriptionUsageCard({
  agent,
  onRefresh,
  refreshing
}: {
  agent: RegisteredAgentDTO;
  onRefresh: () => void;
  refreshing: boolean;
}) {
  const usage = agent.usage;
  const rateLimits = usage?.rateLimits;
  const title = rateLimits?.limit_name ?? rateLimits?.limit_id ?? "Subscription usage";

  return (
    <div className="grid gap-3 rounded-md border border-[#eaebef] bg-white p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="truncate text-xs font-semibold text-[#1d1d1f]">{title}</div>
          <div className="mt-0.5 text-[11px] text-[#8a8d96]">{usageCaption(usage?.status, usage?.checkedAt)}</div>
        </div>
        <button className="dialog-close-button" type="button" title="Refresh usage" onClick={onRefresh} disabled={refreshing}>
          <RefreshCcw size={14} />
        </button>
      </div>
      {rateLimits ? (
        <div className="grid gap-2 sm:grid-cols-2">
          <UsageBucket label="Primary" bucket={rateLimits.primary} />
          <UsageBucket label="Secondary" bucket={rateLimits.secondary} />
        </div>
      ) : (
        <div className="rounded-md border border-dashed border-[#dedfe4] bg-[#fbfbfc] px-3 py-3 text-xs text-[#686b73]">
          {usage?.error || "Rate limits not reported yet"}
        </div>
      )}
    </div>
  );
}

function UsageBucket({ label, bucket }: { label: string; bucket?: CodexRateLimitBucketDTO }) {
  const remaining = numberValue(bucket?.remaining);
  const limit = numberValue(bucket?.limit);
  const usedPercent = numberValue(bucket?.usedPercent) ?? usedPercentFromRemaining(remaining, limit);

  return (
    <div className="rounded-md border border-[#eaebef] bg-[#fbfbfc] p-2">
      <div className="flex items-center justify-between gap-2 text-xs">
        <span className="font-medium text-[#555d68]">{label}</span>
        <span className="mono text-[#686b73]">{remainingLabel(remaining, limit)}</span>
      </div>
      <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-[#e5e7eb]">
        <div className="h-full rounded-full bg-[#6b7280]" style={{ width: `${Math.min(100, Math.max(0, usedPercent ?? 0))}%` }} />
      </div>
      <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-[#8a8d96]">
        <span>{usedPercent == null ? "n/a" : `${Math.round(usedPercent)}% used`}</span>
        <span>{resetLabel(bucket)}</span>
      </div>
    </div>
  );
}

function usageCaption(status?: string, checkedAt?: string | null) {
  if (status === "available") return checkedAt ? `Updated ${new Date(checkedAt).toLocaleString()}` : "Available";
  if (status === "unavailable") return checkedAt ? `Checked ${new Date(checkedAt).toLocaleString()}` : "Unavailable";
  return "Not reported yet";
}

function remainingLabel(remaining?: number, limit?: number) {
  if (remaining != null && limit != null) return `${formatNumber(remaining)} / ${formatNumber(limit)}`;
  if (remaining != null) return `${formatNumber(remaining)} left`;
  if (limit != null) return `${formatNumber(limit)} limit`;
  return "n/a";
}

function resetLabel(bucket?: CodexRateLimitBucketDTO) {
  const reset = bucket?.resetInSeconds ?? bucket?.reset_in_seconds;
  if (typeof reset === "number") return `reset ${Math.ceil(reset / 60)}m`;
  return "";
}

function usedPercentFromRemaining(remaining?: number, limit?: number) {
  if (remaining == null || limit == null || limit <= 0) return undefined;
  return ((limit - remaining) / limit) * 100;
}

function numberValue(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function formatNumber(value: number) {
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(value);
}

function authModeLabel(mode: RegisteredAgentDTO["authMode"]) {
  return mode === "auth_json" ? "auth.json" : mode;
}

function statusLabel(status: RegisteredAgentDTO["credentialStatus"]) {
  switch (status) {
    case "configured":
      return "Configured";
    case "login_started":
      return "Login started";
    case "failed":
      return "Failed";
    default:
      return "Pending";
  }
}

function mcpStatusLabel(status: RegisteredAgentDTO["mcpInstallStatus"]) {
  switch (status) {
    case "configured":
      return "Configured";
    case "installing":
      return "Installing";
    case "failed":
      return "Failed";
    default:
      return "Pending";
  }
}
