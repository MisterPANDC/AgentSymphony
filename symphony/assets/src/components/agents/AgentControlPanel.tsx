import { ChangeEvent, FormEvent, useMemo, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, CheckCircle2, FileText, KeyRound, Plus, RefreshCcw, Search, Server, Terminal, Upload, X } from "lucide-react";
import { createAgentMcpServer, listAgents, refreshAgentUsage, registerAgent } from "../../api/agents";
import type { AgentAuthMode, AgentMcpRegistryDTO, AvailableAgentDTO, CodexRateLimitBucketDTO, RegisteredAgentDTO } from "../../types/agent";

const fallbackAgents: AvailableAgentDTO[] = [
  {
    provider: "codex",
    label: "Codex",
    description: "OpenAI Codex CLI agent",
    modes: ["subscription", "api", "auth_json"]
  }
];

export function AgentControlPanel() {
  const queryClient = useQueryClient();
  const agents = useQuery({ queryKey: ["agents"], queryFn: listAgents });
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
              <Dialog.Content className="fixed left-1/2 top-16 z-40 w-[min(720px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl">
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

                    <div className="grid gap-2 rounded-md border border-[#eaebef] bg-[#fbfbfc] p-3">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="text-xs font-semibold text-[#1d1d1f]">MCP</div>
                          <div className="mt-0.5 text-[11px] text-[#686b73]">{mcpRegistry.path || "agent-mcp.json"}</div>
                        </div>
                        <button className="text-button" type="button" onClick={() => setMcpDialogOpen(true)}>
                          <Plus size={14} /> Add MCP
                        </button>
                      </div>
                      {mcpServerNames.length > 0 ? (
                        <div className="grid gap-1">
                          {mcpServerNames.map((name) => (
                            <label key={name} className="flex items-center justify-between gap-3 rounded-md border border-[#eaebef] bg-white px-3 py-2 text-xs">
                              <span className="min-w-0">
                                <span className="block truncate font-medium text-[#555d68]">{name}</span>
                                <span className="mono block truncate text-[11px] text-[#8a8d96]">{mcpRegistry.mcpServers[name]?.command}</span>
                              </span>
                              <input
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
                        <div className="rounded-md border border-dashed border-[#dedfe4] bg-white px-3 py-3 text-xs text-[#686b73]">
                          No MCP servers configured
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
  const [name, setName] = useState("");
  const [command, setCommand] = useState("");
  const [args, setArgs] = useState("[]");
  const [env, setEnv] = useState("{}");
  const [error, setError] = useState<string | null>(null);
  const createMcp = useMutation({
    mutationFn: createAgentMcpServer,
    onSuccess: () => {
      setName("");
      setCommand("");
      setArgs("[]");
      setEnv("{}");
      setError(null);
      onChanged();
    },
    onError: (error) => setError(error.message)
  });
  const serverNames = Object.keys(registry.mcpServers).sort();

  function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);

    let parsedArgs: string[];
    let parsedEnv: Record<string, string>;
    try {
      parsedArgs = JSON.parse(args || "[]");
      parsedEnv = JSON.parse(env || "{}");
    } catch {
      setError("Args and env must be valid JSON");
      return;
    }

    if (!Array.isArray(parsedArgs) || !parsedArgs.every((item) => typeof item === "string")) {
      setError("Args must be a JSON string array");
      return;
    }

    if (!parsedEnv || Array.isArray(parsedEnv) || typeof parsedEnv !== "object") {
      setError("Env must be a JSON object");
      return;
    }

    createMcp.mutate({
      name,
      command,
      args: parsedArgs,
      env: parsedEnv
    });
  }

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/10" />
        <Dialog.Content className="fixed left-1/2 top-16 z-50 w-[min(760px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl">
          <Dialog.Title className="sr-only">MCP servers</Dialog.Title>
          <div className="flex items-center justify-between gap-3 border-b border-[#eaebef] px-3 py-2">
            <div className="min-w-0">
              <div className="text-sm font-semibold">MCP servers</div>
              <div className="mono mt-0.5 truncate text-[11px] text-[#8a8d96]">{registry.path || "agent-mcp.json"}</div>
            </div>
            <Dialog.Close className="dialog-close-button" title="Close MCP servers">
              <X size={15} />
            </Dialog.Close>
          </div>
          <div className="grid max-h-[calc(100vh-160px)] gap-3 overflow-auto p-3">
            <div className="grid gap-2">
              {serverNames.length > 0 ? (
                serverNames.map((serverName) => (
                  <div key={serverName} className="rounded-md border border-[#eaebef] bg-[#fbfbfc] px-3 py-2">
                    <div className="text-sm font-medium">{serverName}</div>
                    <div className="mono mt-1 truncate text-xs text-[#686b73]">{registry.mcpServers[serverName]?.command}</div>
                  </div>
                ))
              ) : (
                <div className="rounded-md border border-dashed border-[#dedfe4] bg-[#fbfbfc] px-3 py-4 text-center text-sm text-[#686b73]">
                  No MCP servers configured
                </div>
              )}
            </div>

            <form className="grid gap-2 border-t border-[#eaebef] pt-3" onSubmit={submit}>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <input
                  className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                  placeholder="name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                />
                <input
                  className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                  placeholder="command"
                  value={command}
                  onChange={(event) => setCommand(event.target.value)}
                />
              </div>
              <input
                className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                placeholder='args JSON, e.g. ["--stdio"]'
                value={args}
                onChange={(event) => setArgs(event.target.value)}
              />
              <textarea
                className="min-h-20 resize-y rounded-md border border-[#dedfe4] bg-white px-3 py-2 text-xs outline-none focus:border-[#9ca3af]"
                placeholder='{"TOKEN":"..."}'
                value={env}
                onChange={(event) => setEnv(event.target.value)}
              />
              {(error || createMcp.isError) && (
                <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">{error || createMcp.error?.message}</div>
              )}
              <div className="flex justify-end">
                <button className="text-button" type="submit" disabled={createMcp.isPending || !name.trim() || !command.trim()}>
                  <Plus size={14} /> Add MCP
                </button>
              </div>
            </form>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function OpenAILogo({ size = 16 }: { size?: number }) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M17.9 10.9V6.7a5.1 5.1 0 0 0-8.5-3.8A5.1 5.1 0 0 0 3.3 9a5.1 5.1 0 0 0 .8 8.2v.1a5.1 5.1 0 0 0 8.5 3.8 5.1 5.1 0 0 0 6.1-6.1 5.1 5.1 0 0 0-.8-4.1Zm-5.3 8.8a3.8 3.8 0 0 1-6.2-2.9v-.3l3.9 2.2a.7.7 0 0 0 .7 0l1.6-.9v1.9Zm4.8-4.2a3.8 3.8 0 0 1-3.4 4.1v-4.5a.7.7 0 0 0-.4-.6L12 13.6l1.7-1 3.7 2.1v.8ZM5 16.1a3.8 3.8 0 0 1-.6-6.8l3.9 2.2a.7.7 0 0 0 .7 0l1.6-.9v2l-3.7 2.1a.7.7 0 0 0-.4.6v1.8L5 16.1Zm1.6-11.7a3.8 3.8 0 0 1 2.1-.1v4.5a.7.7 0 0 0 .4.6l1.6.9-1.7 1-3.7-2.1A3.8 3.8 0 0 1 6.6 4.4Zm10.8 6.3-3.8-2.2a.7.7 0 0 0-.7 0l-1.6.9v-2l3.7-2.1a.7.7 0 0 0 .4-.6V3a3.8 3.8 0 0 1 1.9 7.7Zm-8.1 3 2.7-1.6 2.7 1.6v3.1L12 18.4l-2.7-1.6v-3.1Zm2.7-3.2-2.7-1.6V5.8L12 4.2l2.7 1.6v3.1L12 10.5Z"
        fill="currentColor"
      />
    </svg>
  );
}

function AgentList({
  agents,
  loading,
  onRefreshUsage,
  refreshingAgentId
}: {
  agents: RegisteredAgentDTO[];
  loading: boolean;
  onRefreshUsage: (id: string) => void;
  refreshingAgentId?: string;
}) {
  if (loading) {
    return <div className="px-4 py-8 text-center text-sm text-[#686b73]">Loading agents</div>;
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
