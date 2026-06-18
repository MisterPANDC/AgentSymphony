import { ChangeEvent, FormEvent, ReactNode, useEffect, useMemo, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, CheckCircle2, Download, FileText, KeyRound, Package, Plus, RefreshCcw, RotateCcw, Search, Server, Settings, Terminal, Trash2, Upload, X } from "lucide-react";
import { deleteAgent, installAgentAsset, listAgents, loginAgent, refreshAgentUsage, registerAgent, removeAgentAsset, saveAgentAssetRegistry, saveAgentMcpRegistry, updateAgent } from "../../api/agents";
import { sendAiChatMessage } from "../../api/aiChat";
import type { AgentAssetDTO, AgentAssetRegistryDTO, AgentAuthMode, AgentMcpRegistryDTO, AgentMcpServerDTO, AvailableAgentDTO, CodexRateLimitBucketDTO, RegisteredAgentDTO } from "../../types/agent";
import { OpenAILogo } from "./AgentProviderLogo";

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

type PluginConfigTab = "plugins" | "skills" | "mcp";

export function AgentControlPanel() {
  const queryClient = useQueryClient();
  const agents = useQuery({ queryKey: ["agents"], queryFn: listAgents, retry: false });
  const [dialogOpen, setDialogOpen] = useState(false);
  const [pluginDialogOpen, setPluginDialogOpen] = useState(false);
  const [pluginDialogTab, setPluginDialogTab] = useState<PluginConfigTab>("plugins");
  const [settingsAgentId, setSettingsAgentId] = useState<string | null>(null);
  const [detailAgentId, setDetailAgentId] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [selectedProvider, setSelectedProvider] = useState<"codex">("codex");
  const [agentName, setAgentName] = useState("");
  const [authMode, setAuthMode] = useState<AgentAuthMode>("subscription");
  const [apiKey, setApiKey] = useState("");
  const [authJson, setAuthJson] = useState("");
  const [authJsonName, setAuthJsonName] = useState("");
  const [selectedMcpServerNames, setSelectedMcpServerNames] = useState<string[]>([]);
  const [selectedSkillNames, setSelectedSkillNames] = useState<string[]>([]);
  const [selectedPluginNames, setSelectedPluginNames] = useState<string[]>([]);

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
      setSelectedSkillNames([]);
      setSelectedPluginNames([]);
      queryClient.invalidateQueries({ queryKey: ["agents"] });
      window.setTimeout(() => queryClient.invalidateQueries({ queryKey: ["agents"] }), 1500);
    }
  });

  const refreshUsage = useMutation({
    mutationFn: refreshAgentUsage,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["agents"] })
  });

  const relogin = useMutation({
    mutationFn: loginAgent,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["agents"] });
      window.setTimeout(() => queryClient.invalidateQueries({ queryKey: ["agents"] }), 1500);
    }
  });

  const removeAgent = useMutation({
    mutationFn: deleteAgent,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["agents"] })
  });

  const saveAgent = useMutation({
    mutationFn: updateAgent,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["agents"] });
      window.setTimeout(() => queryClient.invalidateQueries({ queryKey: ["agents"] }), 1000);
    }
  });

  const installAsset = useMutation({
    mutationFn: installAgentAsset,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["agents"] });
      window.setTimeout(() => queryClient.invalidateQueries({ queryKey: ["agents"] }), 1000);
    }
  });

  const removeAsset = useMutation({
    mutationFn: removeAgentAsset,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["agents"] });
      window.setTimeout(() => queryClient.invalidateQueries({ queryKey: ["agents"] }), 1000);
    }
  });

  function submitRegistration(event: FormEvent) {
    event.preventDefault();
    register.mutate({
      provider: selectedProvider,
      name: agentName || undefined,
      authMode,
      apiKey: authMode === "api" ? apiKey : undefined,
      authJson: authMode === "auth_json" ? authJson : undefined,
      mcpServerNames: selectedMcpServerNames,
      skillNames: selectedSkillNames,
      pluginNames: selectedPluginNames
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
  const assetRegistry = agents.data?.assets ?? { path: "", skills: {}, plugins: {} };
  const skillNames = Object.keys(assetRegistry.skills).sort();
  const pluginNames = Object.keys(assetRegistry.plugins).sort();
  const settingsAgent = (agents.data?.agents ?? []).find((agent) => agent.id === settingsAgentId) ?? null;
  const detailAgent = (agents.data?.agents ?? []).find((agent) => agent.id === detailAgentId) ?? null;

  function openPluginConfig(tab: PluginConfigTab) {
    setPluginDialogTab(tab);
    setPluginDialogOpen(true);
  }

  return (
    <div className="space-y-4">
      <section className="panel">
        <div className="panel-header">
          <h1 className="flex items-center gap-2 text-sm font-semibold"><Bot size={15} /> Agents</h1>
          <div className="flex items-center gap-2">
            <button className="text-button" type="button" onClick={() => openPluginConfig("plugins")}><Package size={14} /> Plugin</button>
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
                        <button className="text-button" type="button" onClick={() => openPluginConfig("mcp")}>
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

                    <div className="grid gap-3 rounded-md border border-[#eaebef] bg-[#fbfbfc] p-3">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="flex items-center gap-1.5 text-xs font-semibold text-[#1d1d1f]">
                            <Package size={13} />
                            Plugin & skill
                          </div>
                          <div className="mono mt-0.5 text-[11px] text-[#686b73]">
                            {assetRegistry.pluginPath || "agent-plugin.json"} · {assetRegistry.skillPath || "agent-skill.json"}
                          </div>
                        </div>
                        <button className="text-button" type="button" onClick={() => openPluginConfig("plugins")}>
                          <Plus size={14} /> Configure
                        </button>
                      </div>
                      {skillNames.length > 0 || pluginNames.length > 0 ? (
                        <div className="grid gap-2">
                          <AssetCheckboxGroup
                            title="Skills"
                            names={skillNames}
                            assets={assetRegistry.skills}
                            selected={selectedSkillNames}
                            onSelectedChange={setSelectedSkillNames}
                          />
                          <AssetCheckboxGroup
                            title="Plugins"
                            names={pluginNames}
                            assets={assetRegistry.plugins}
                            selected={selectedPluginNames}
                            onSelectedChange={setSelectedPluginNames}
                          />
                        </div>
                      ) : (
                        <div className="rounded-md border border-dashed border-[#dedfe4] bg-white px-3 py-4 text-xs text-[#686b73]">
                          No shared plugin or skill definitions yet. Configure Plugin first, then select them for this agent.
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
          onDelete={(agent) => {
            if (window.confirm(`Delete the ${agent.name} agent registration?`)) {
              removeAgent.mutate(agent.id);
            }
          }}
          onSettings={(agent) => setSettingsAgentId(agent.id)}
          onDetails={(agent) => setDetailAgentId(agent.id)}
          deletingAgentId={removeAgent.isPending ? removeAgent.variables : undefined}
        />
        {(removeAgent.isError || relogin.isError || saveAgent.isError || installAsset.isError || removeAsset.isError) && (
          <div className="mx-3 mb-3 rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">
            {removeAgent.error?.message || relogin.error?.message || saveAgent.error?.message || installAsset.error?.message || removeAsset.error?.message}
          </div>
        )}
      </section>
      {detailAgent && (
        <AgentDetailDialog
          agent={detailAgent}
          open={Boolean(detailAgent)}
          onOpenChange={(open) => !open && setDetailAgentId(null)}
        />
      )}
      {settingsAgent && (
        <AgentSettingsDialog
          agent={settingsAgent}
          open={Boolean(settingsAgent)}
          onOpenChange={(open) => !open && setSettingsAgentId(null)}
          assetRegistry={assetRegistry}
          mcpRegistry={mcpRegistry}
          onSave={(input) => saveAgent.mutate(input)}
          onRelogin={(input) => relogin.mutate(input)}
          onRefreshUsage={(id) => refreshUsage.mutate(id)}
          onInstallAsset={(input) => installAsset.mutate(input)}
          onRemoveAsset={(input) => removeAsset.mutate(input)}
          onOpenConfig={(tab) => {
            setSettingsAgentId(null);
            openPluginConfig(tab);
          }}
          saving={saveAgent.isPending}
          relogging={relogin.isPending && reloginAgentId(relogin.variables) === settingsAgent.id}
          refreshing={refreshUsage.isPending && refreshUsage.variables === settingsAgent.id}
          pendingAsset={installAsset.isPending ? installAsset.variables : removeAsset.isPending ? removeAsset.variables : undefined}
          pendingMcpAgentId={saveAgent.isPending ? saveAgent.variables?.id : undefined}
        />
      )}
      <PluginManagerDialog
        open={pluginDialogOpen}
        onOpenChange={setPluginDialogOpen}
        activeTab={pluginDialogTab}
        onActiveTabChange={setPluginDialogTab}
        assetRegistry={assetRegistry}
        mcpRegistry={mcpRegistry}
        onChanged={() => queryClient.invalidateQueries({ queryKey: ["agents"] })}
      />
    </div>
  );
}

function AssetCheckboxGroup({
  title,
  names,
  assets,
  selected,
  onSelectedChange
}: {
  title: string;
  names: string[];
  assets: Record<string, AgentAssetDTO>;
  selected: string[];
  onSelectedChange: (names: string[]) => void;
}) {
  if (names.length === 0) return null;

  return (
    <div className="grid gap-1">
      <div className="text-[11px] font-semibold uppercase text-[#8a8d96]">{title}</div>
      {names.map((name) => (
        <label key={name} className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-3 rounded-md border border-[#eaebef] bg-white px-3 py-2.5 text-xs">
          <span className="grid min-w-0 gap-1">
            <span className="truncate font-medium text-[#555d68]">{name}</span>
            <span className="mono block truncate text-[11px] text-[#686b73]">{assetSourceLabel(assets[name])}</span>
          </span>
          <input
            className="mt-1"
            type="checkbox"
            checked={selected.includes(name)}
            onChange={(event) => {
              onSelectedChange(event.target.checked ? [...selected, name] : selected.filter((item) => item !== name));
            }}
          />
        </label>
      ))}
    </div>
  );
}

function PluginManagerDialog({
  open,
  onOpenChange,
  activeTab,
  onActiveTabChange,
  assetRegistry,
  mcpRegistry,
  onChanged
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  activeTab: PluginConfigTab;
  onActiveTabChange: (tab: PluginConfigTab) => void;
  assetRegistry: AgentAssetRegistryDTO;
  mcpRegistry: AgentMcpRegistryDTO;
  onChanged: () => void;
}) {
  const tabs: Array<{ id: PluginConfigTab; label: string; icon: typeof Package; count: number; path: string }> = [
    { id: "plugins", label: "Plugin", icon: Package, count: Object.keys(assetRegistry.plugins).length, path: assetRegistry.pluginPath || "agent-plugin.json" },
    { id: "skills", label: "Skill", icon: FileText, count: Object.keys(assetRegistry.skills).length, path: assetRegistry.skillPath || "agent-skill.json" },
    { id: "mcp", label: "MCP", icon: Server, count: Object.keys(mcpRegistry.mcpServers).length, path: mcpRegistry.path || "agent-mcp.json" }
  ];
  const active = tabs.find((tab) => tab.id === activeTab) ?? tabs[0];
  const ActiveIcon = active.icon;

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/10" />
        <Dialog.Content className="fixed left-1/2 top-8 z-50 w-[min(980px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl outline-none">
          <Dialog.Title className="sr-only">Plugin configuration</Dialog.Title>
          <div className="flex items-center justify-between gap-3 border-b border-[#eaebef] px-4 py-3">
            <div className="flex min-w-0 items-center gap-3">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-[#fbfbfc] text-[#555d68]">
                <ActiveIcon size={16} />
              </span>
              <div className="min-w-0">
                <div className="text-sm font-semibold">Plugin</div>
                <div className="mono mt-0.5 truncate text-[11px] text-[#8a8d96]">{active.path}</div>
              </div>
            </div>
            <Dialog.Close className="dialog-close-button" title="Close plugin configuration">
              <X size={15} />
            </Dialog.Close>
          </div>

          <div className="grid max-h-[calc(100vh-96px)] grid-cols-1 overflow-hidden md:grid-cols-[190px_minmax(0,1fr)]">
            <div className="grid content-start gap-1 border-b border-[#eaebef] bg-[#fbfbfc] p-2 md:border-b-0 md:border-r">
              {tabs.map((tab) => {
                const Icon = tab.icon;
                const selected = tab.id === activeTab;

                return (
                  <button
                    key={tab.id}
                    className={`grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-2 rounded-md px-2.5 py-2 text-left text-sm transition-colors ${
                      selected ? "bg-white text-[#1d1d1f] shadow-sm ring-1 ring-[#dedfe4]" : "text-[#555d68] hover:bg-white"
                    }`}
                    type="button"
                    onClick={() => onActiveTabChange(tab.id)}
                  >
                    <Icon size={14} className="text-[#686b73]" />
                    <span className="truncate font-medium">{tab.label}</span>
                    <span className="text-xs text-[#686b73]">{tab.count}</span>
                  </button>
                );
              })}
            </div>

            <div className="min-h-0 overflow-auto p-3">
              {activeTab === "plugins" && (
                <AssetKindConfigPanel
                  kind="plugins"
                  title="Plugin"
                  registry={assetRegistry}
                  onChanged={onChanged}
                />
              )}
              {activeTab === "skills" && (
                <AssetKindConfigPanel
                  kind="skills"
                  title="Skill"
                  registry={assetRegistry}
                  onChanged={onChanged}
                />
              )}
              {activeTab === "mcp" && <McpConfigPanel registry={mcpRegistry} onChanged={onChanged} />}
            </div>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function AssetKindConfigPanel({
  kind,
  title,
  registry,
  onChanged
}: {
  kind: "skills" | "plugins";
  title: string;
  registry: AgentAssetRegistryDTO;
  onChanged: () => void;
}) {
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
  const [gitUrl, setGitUrl] = useState("");
  const [markdown, setMarkdown] = useState("");
  const [markdownFilename, setMarkdownFilename] = useState("");
  const [error, setError] = useState<string | null>(null);
  const assets = kind === "skills" ? registry.skills : registry.plugins;
  const saveAssets = useMutation({
    mutationFn: saveAgentAssetRegistry,
    onSuccess: () => {
      setName("");
      setGitUrl("");
      setMarkdown("");
      setMarkdownFilename("");
      setError(null);
      onChanged();
    },
    onError: (error) => setError(error.message)
  });
  const buildSkillChat = useMutation({
    mutationFn: () =>
      sendAiChatMessage(
        "帮我创建一个 Codex skill。请先询问我 skill 的用途、触发场景、输入输出和示例，然后根据回答生成完整的 SKILL.md 内容。"
      ),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["ai-chat"] }),
    onError: (error) => setError(error.message)
  });
  const names = Object.keys(assets).sort();

  useEffect(() => {
    setError(null);
  }, [kind, names.length]);

  function submitPlugin(event: FormEvent) {
    event.preventDefault();
    setError(null);

    const trimmedName = name.trim();
    const trimmedGitUrl = gitUrl.trim();
    if (!validMcpServerName(trimmedName)) {
      setError("Plugin name must use letters, numbers, dots, dashes, or underscores.");
      return;
    }
    if (!trimmedGitUrl) {
      setError("Plugin git URL is required.");
      return;
    }

    saveAssets.mutate({
      skills: registry.skills,
      plugins: { ...registry.plugins, [trimmedName]: { git_url: trimmedGitUrl } }
    });
  }

  function submitSkill(event: FormEvent) {
    event.preventDefault();
    setError(null);

    const trimmedName = name.trim();
    if (!validMcpServerName(trimmedName)) {
      setError("Skill name must use letters, numbers, dots, dashes, or underscores.");
      return;
    }
    if (!markdown.trim()) {
      setError("Upload a Markdown file first.");
      return;
    }
    saveAssets.mutate({
      skills: { ...registry.skills, [trimmedName]: { content: markdown, filename: markdownFilename || `${trimmedName}.md` } },
      plugins: registry.plugins
    });
  }

  async function loadSkillMarkdown(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    const text = await file.text();
    setMarkdown(text);
    setMarkdownFilename(file.name);
    if (!name.trim()) setName(file.name.replace(/\.[^.]+$/, ""));
    setError(null);
  }

  return (
    <div className="grid gap-3">
      {registry.error && (
        <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">{registry.error}</div>
      )}

      <AssetDefinitionList title={`${title} definitions`} assets={assets} />

      {kind === "plugins" ? (
      <form className="grid gap-3 border-t border-[#eaebef] pt-3" onSubmit={submitPlugin}>
          <div>
            <div className="text-xs font-semibold text-[#1d1d1f]">Add plugin</div>
            <div className="mt-0.5 text-[11px] text-[#686b73]">Saved in agent-plugin.json. Selected agents will clone and link the repository.</div>
          </div>
        <div className="grid gap-2 sm:grid-cols-[180px_minmax(0,1fr)]">
          <input
            className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
            placeholder="Plugin name"
            value={name}
            onChange={(event) => {
              setName(event.target.value);
              setError(null);
            }}
          />
          <input
            className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
            placeholder="https://github.com/org/plugin.git"
            value={gitUrl}
            onChange={(event) => {
              setGitUrl(event.target.value);
              setError(null);
            }}
          />
        </div>
        {(error || saveAssets.isError) && (
          <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">
            {error || saveAssets.error?.message}
          </div>
        )}
        <div className="flex justify-end">
          <button className="text-button" type="submit" disabled={saveAssets.isPending || !name.trim() || !gitUrl.trim()}>
            <Package size={14} /> Add plugin
          </button>
        </div>
      </form>
      ) : (
      <form className="grid gap-3 border-t border-[#eaebef] pt-3" onSubmit={submitSkill}>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <div className="text-xs font-semibold text-[#1d1d1f]">Add skill</div>
            <div className="mt-0.5 text-[11px] text-[#686b73]">Upload a Markdown SKILL.md file, or start drafting one in chat.</div>
          </div>
          <button className="text-button" type="button" disabled={buildSkillChat.isPending} onClick={() => buildSkillChat.mutate()}>
            <Terminal size={14} /> Build in chat
          </button>
        </div>
        <div className="grid gap-2 sm:grid-cols-[180px_minmax(0,1fr)]">
          <input
            className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
            placeholder="Skill name"
            value={name}
            onChange={(event) => {
              setName(event.target.value);
              setError(null);
            }}
          />
          <label className="flex h-9 cursor-pointer items-center justify-between gap-3 rounded-md border border-[#dedfe4] bg-white px-3 text-sm text-[#555d68]">
            <span className="min-w-0 truncate">{markdownFilename || "Choose Markdown file"}</span>
            <Upload size={14} className="shrink-0 text-[#686b73]" />
            <input className="hidden" type="file" accept=".md,text/markdown,text/plain" onChange={loadSkillMarkdown} />
          </label>
        </div>
        {markdown && (
          <div className="mono max-h-32 overflow-auto rounded-md border border-[#eaebef] bg-[#fbfbfc] px-3 py-2 text-xs leading-5 text-[#555d68]">
            {markdown.slice(0, 1200)}
          </div>
        )}
        {(error || saveAssets.isError || buildSkillChat.isError) && (
          <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">
            {error || saveAssets.error?.message || buildSkillChat.error?.message}
          </div>
        )}
        <div className="flex justify-end">
          <button className="text-button" type="submit" disabled={saveAssets.isPending || !name.trim() || !markdown.trim()}>
            <FileText size={14} /> Add skill
          </button>
        </div>
      </form>
      )}
    </div>
  );
}

function McpConfigPanel({ registry, onChanged }: { registry: AgentMcpRegistryDTO; onChanged: () => void }) {
  const [mcpJson, setMcpJson] = useState("");
  const [error, setError] = useState<string | null>(null);
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
    setMcpJson(serverNames.length > 0 ? formattedRegistry : "");
    setError(null);
  }, [formattedRegistry, serverNames.length]);

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
    <div className="grid gap-3">
      {registry.error && (
        <div className="rounded-md border border-[#efcaca] bg-[#fff8f8] px-3 py-2 text-xs text-[#9b1c1c]">{registry.error}</div>
      )}

      <div className="grid gap-2">
        <div>
          <div>
            <div className="flex items-center gap-1.5 text-xs font-semibold text-[#1d1d1f]">
              <span>MCP definitions</span>
              <span className="text-xs font-normal text-[#686b73]">{serverNames.length}</span>
            </div>
          </div>
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
        <div className="flex justify-end">
          <button className="text-button" type="submit" disabled={submitDisabled}>
            <Server size={14} /> Add MCP
          </button>
        </div>
      </form>
    </div>
  );
}

function AssetDefinitionList({ title, assets }: { title: string; assets: Record<string, AgentAssetDTO> }) {
  const names = Object.keys(assets).sort();

  return (
    <div className="grid gap-2">
      <div className="flex items-center gap-1.5">
        <div className="text-xs font-semibold text-[#1d1d1f]">{title}</div>
        <span className="text-xs text-[#686b73]">{names.length}</span>
      </div>
      {names.length > 0 ? (
        <div className="grid gap-2">
          {names.map((name) => (
            <div key={name} className="grid gap-1 rounded-md border border-[#eaebef] bg-[#fbfbfc] px-3 py-2.5">
              <div className="truncate text-sm font-medium text-[#1d1d1f]">{name}</div>
              <div className="mono min-w-0 truncate rounded border border-[#eaebef] bg-white px-2 py-1.5 text-xs text-[#555d68]">{assetSourceLabel(assets[name])}</div>
            </div>
          ))}
        </div>
      ) : (
        <div className="rounded-md border border-dashed border-[#dedfe4] bg-[#fbfbfc] px-3 py-3 text-center text-sm text-[#686b73]">No {title.toLowerCase()} defined.</div>
      )}
    </div>
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

function assetSourceLabel(asset?: AgentAssetDTO) {
  if (!asset) return "No source";
  return asset.git_url || asset.path || asset.filename || (asset.content ? "Uploaded Markdown" : "No source");
}

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

function AgentList({
  agents,
  error,
  loading,
  onDelete,
  onSettings,
  onDetails,
  deletingAgentId
}: {
  agents: RegisteredAgentDTO[];
  error?: string | null;
  loading: boolean;
  onDelete: (agent: RegisteredAgentDTO) => void;
  onSettings: (agent: RegisteredAgentDTO) => void;
  onDetails: (agent: RegisteredAgentDTO) => void;
  deletingAgentId?: string;
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
    <div className="grid grid-cols-[repeat(auto-fit,minmax(300px,380px))] justify-start gap-3 p-3">
      {agents.map((agent) => {
        return (
          <div
            key={agent.id}
            className="grid w-full max-w-[380px] min-w-0 cursor-pointer gap-4 rounded-md border border-[#eaebef] bg-white p-4 transition-colors hover:bg-[#fbfbfc] focus-visible:outline focus-visible:outline-1 focus-visible:outline-[#cfd4dc]"
            role="button"
            tabIndex={0}
            onClick={() => onDetails(agent)}
            onKeyDown={(event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                onDetails(agent);
              }
            }}
          >
            <div className="flex items-center justify-between gap-3">
              <div className="flex min-w-0 items-center gap-1.5">
                <span className="grid h-8 w-8 shrink-0 place-items-center text-[#555d68]">
                  <OpenAILogo size={19} />
                </span>
                <div className="flex min-w-0 items-baseline gap-2">
                  <div className="truncate text-base font-semibold text-[#1d1d1f]">{agent.name}</div>
                  <div className="shrink-0 text-[11px] font-medium uppercase tracking-[0.02em] text-[#8a8d96]">{authModeLabel(agent.authMode)}</div>
                </div>
              </div>
              <div className="flex h-8 shrink-0 items-center gap-1">
                <button
                  className="dialog-close-button"
                  type="button"
                  title="Agent settings"
                  aria-label={`Open ${agent.name} settings`}
                  onKeyDown={(event) => event.stopPropagation()}
                  onClick={(event) => {
                    event.stopPropagation();
                    onSettings(agent);
                  }}
                >
                  <Settings size={14} />
                </button>
                <button
                  className="dialog-close-button"
                  type="button"
                  title="Delete agent registration"
                  aria-label={`Delete ${agent.name} agent registration`}
                  disabled={deletingAgentId === agent.id}
                  onKeyDown={(event) => event.stopPropagation()}
                  onClick={(event) => {
                    event.stopPropagation();
                    onDelete(agent);
                  }}
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
            <AgentUsageSummary agent={agent} />
            {agent.lastLoginMessage && agent.credentialStatus === "failed" && (
              <div className="rounded-md border border-[#efcaca] bg-white px-3 py-2 text-xs text-[#9b1c1c]">{agent.lastLoginMessage}</div>
            )}
            {agent.mcpInstallMessage && agent.mcpInstallStatus === "failed" && (
              <div className="rounded-md border border-[#efcaca] bg-white px-3 py-2 text-xs text-[#9b1c1c]">{agent.mcpInstallMessage}</div>
            )}
            {agent.assetInstallMessage && agent.assetInstallStatus === "failed" && (
              <div className="rounded-md border border-[#efcaca] bg-white px-3 py-2 text-xs text-[#9b1c1c]">{agent.assetInstallMessage}</div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function AgentDetailDialog({ agent, open, onOpenChange }: { agent: RegisteredAgentDTO; open: boolean; onOpenChange: (open: boolean) => void }) {
  const installedMcp = agent.mcpInstalledServers ?? [];

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="issue-detail-overlay" />
        <Dialog.Content className="issue-detail-dialog">
          <Dialog.Description className="issue-detail-title--hidden">Agent details for {agent.name}</Dialog.Description>
          <div className="issue-detail-dialog-content">
            <div className="issue-detail-pane">
              <div className="issue-detail-dialog-body">
                <div className="issue-detail-dialog-header">
                  <div className="min-w-0 flex-1">
                    <div className="flex min-w-0 items-center gap-3">
                      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-[#fbfbfc] text-[#555d68]">
                        <OpenAILogo size={17} />
                      </span>
                      <div className="min-w-0">
                        <Dialog.Title className="truncate text-lg font-semibold text-[#1d1d1f]">{agent.name}</Dialog.Title>
                        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs">
                          <span className="rounded border border-[#dedfe4] bg-[#fbfbfc] px-1.5 py-0.5 font-medium uppercase text-[#686b73]">{authModeLabel(agent.authMode)}</span>
                        </div>
                      </div>
                    </div>
                  </div>
                  <div className="pane-actions" aria-label="Agent detail actions">
                    <Dialog.Close className="dialog-close-button" type="button" aria-label="Close agent details" title="Close agent details">
                      <X size={15} />
                    </Dialog.Close>
                  </div>
                </div>

                <div className="grid divide-y divide-[#eaebef]">
                  <AgentDetailSection title="Overview">
                    <AgentDetailRows
                      rows={[
                        ["Agent home", agent.codexHome],
                        ["Provider", agent.provider],
                        ["Auth mode", authModeLabel(agent.authMode)],
                        ["Created", formatAgentDate(agent.insertedAt)],
                        ["Updated", formatAgentDate(agent.updatedAt)]
                      ]}
                    />
                  </AgentDetailSection>

                  <AgentDetailSection title="Usage">
                    {agent.authMode === "subscription" ? <AgentDetailUsage agent={agent} /> : <div className="text-sm text-[#686b73]">Usage is not applicable for {authModeLabel(agent.authMode)} agents.</div>}
                  </AgentDetailSection>

                  <AgentDetailSection title="Plugin">
                    <AgentDetailNameList names={agent.pluginNames ?? []} empty="No plugins selected." />
                  </AgentDetailSection>

                  <AgentDetailSection title="Skill">
                    <AgentDetailNameList names={agent.skillNames ?? []} empty="No skills selected." />
                  </AgentDetailSection>

                  <AgentDetailSection title="MCP">
                    <AgentDetailNameList names={agent.mcpServerNames ?? []} empty="No MCP servers selected." />
                    {installedMcp.length > 0 && (
                      <div className="mt-3 grid gap-2">
                        <div className="text-[11px] font-semibold uppercase text-[#8a8d96]">Installed servers</div>
                        {installedMcp.map((server) => (
                          <div key={server.name} className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 border-t border-[#eaebef] py-2 first:border-t-0">
                            <span className="truncate text-sm font-medium text-[#555d68]">{server.name}</span>
                            <span className="text-xs text-[#8a8d96]">{server.enabled ? "enabled" : "disabled"} · {server.registered ? "registered" : "unregistered"}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </AgentDetailSection>

                  {(agent.lastLoginMessage || agent.mcpInstallMessage || agent.assetInstallMessage) && (
                    <AgentDetailSection title="Messages">
                      <div className="grid gap-2">
                        {agent.lastLoginMessage && <AgentDetailMessage label="Credential" message={agent.lastLoginMessage} />}
                        {agent.mcpInstallMessage && <AgentDetailMessage label="MCP" message={agent.mcpInstallMessage} />}
                        {agent.assetInstallMessage && <AgentDetailMessage label="Assets" message={agent.assetInstallMessage} />}
                      </div>
                    </AgentDetailSection>
                  )}
                </div>
              </div>
            </div>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function AgentDetailSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="grid gap-3 py-4 first:pt-0 last:pb-0">
      <div className="text-xs font-semibold uppercase tracking-[0.02em] text-[#8a8d96]">{title}</div>
      {children}
    </section>
  );
}

function AgentDetailRows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <dl className="grid gap-2 text-sm">
      {rows.map(([label, value]) => (
        <div key={label} className="grid gap-1 sm:grid-cols-[120px_minmax(0,1fr)]">
          <dt className="text-xs font-medium text-[#8a8d96]">{label}</dt>
          <dd className={`${label === "Agent home" ? "mono" : ""} min-w-0 break-words text-[#555d68]`}>{value || "n/a"}</dd>
        </div>
      ))}
    </dl>
  );
}

function AgentDetailNameList({ names, empty }: { names: string[]; empty: string }) {
  if (names.length === 0) return <div className="text-sm text-[#686b73]">{empty}</div>;

  return (
    <div className="flex flex-wrap gap-1.5">
      {names.map((name) => (
        <span key={name} className="rounded border border-[#dedfe4] bg-[#fbfbfc] px-2 py-1 text-xs font-medium text-[#555d68]">
          {name}
        </span>
      ))}
    </div>
  );
}

function AgentDetailUsage({ agent }: { agent: RegisteredAgentDTO }) {
  const usage = agent.usage;
  const rateLimits = usage?.rateLimits;

  if (!rateLimits) {
    return <div className="text-sm text-[#686b73]">{usage?.error || "Rate limits not reported yet."}</div>;
  }

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      <UsageBucket label="Primary" bucket={rateLimits.primary} />
      <UsageBucket label="Secondary" bucket={rateLimits.secondary} />
    </div>
  );
}

function AgentDetailMessage({ label, message }: { label: string; message: string }) {
  return (
    <div className="grid gap-1 rounded-md border border-[#eaebef] bg-[#fbfbfc] px-3 py-2">
      <div className="text-[11px] font-semibold uppercase text-[#8a8d96]">{label}</div>
      <div className="whitespace-pre-wrap break-words text-sm text-[#555d68]">{message}</div>
    </div>
  );
}

function AgentUsageSummary({ agent }: { agent: RegisteredAgentDTO }) {
  const usage = agent.usage;
  const rateLimits = usage?.rateLimits;

  if (agent.authMode !== "subscription") {
    return (
      <div className="grid gap-1">
        <div className="text-xs font-semibold text-[#555d68]">Usage</div>
        <div className="truncate text-sm text-[#686b73]">Not applicable for {authModeLabel(agent.authMode)} agents.</div>
      </div>
    );
  }

  return (
    <div className="grid gap-1">
      <div className="text-xs font-semibold text-[#555d68]">Usage</div>
      {rateLimits ? (
        <div className="truncate text-sm text-[#686b73]">
          Primary {remainingLabel(numberValue(rateLimits.primary?.remaining), numberValue(rateLimits.primary?.limit))}
          {rateLimits.secondary ? ` · Secondary ${remainingLabel(numberValue(rateLimits.secondary.remaining), numberValue(rateLimits.secondary.limit))}` : ""}
        </div>
      ) : (
        <div className="truncate text-sm text-[#686b73]">{usage?.error || "Rate limits not reported yet"}</div>
      )}
    </div>
  );
}

function AgentSettingsDialog({
  agent,
  open,
  onOpenChange,
  assetRegistry,
  mcpRegistry,
  onSave,
  onRelogin,
  onRefreshUsage,
  onInstallAsset,
  onRemoveAsset,
  onOpenConfig,
  saving,
  relogging,
  refreshing,
  pendingAsset,
  pendingMcpAgentId
}: {
  agent: RegisteredAgentDTO;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  assetRegistry: AgentAssetRegistryDTO;
  mcpRegistry: AgentMcpRegistryDTO;
  onSave: (input: { id: string; name?: string; mcpServerNames?: string[] }) => void;
  onRelogin: (input: string | { id: string; apiKey?: string; authJson?: string }) => void;
  onRefreshUsage: (id: string) => void;
  onInstallAsset: (input: { id: string; kind: "skills" | "plugins"; name: string }) => void;
  onRemoveAsset: (input: { id: string; kind: "skills" | "plugins"; name: string }) => void;
  onOpenConfig: (tab: PluginConfigTab) => void;
  saving: boolean;
  relogging: boolean;
  refreshing: boolean;
  pendingAsset?: { id: string; kind: "skills" | "plugins"; name: string };
  pendingMcpAgentId?: string;
}) {
  const [name, setName] = useState(agent.name);
  const [apiKey, setApiKey] = useState("");
  const [authJson, setAuthJson] = useState("");
  const [authJsonName, setAuthJsonName] = useState("");
  const trimmedName = name.trim();

  useEffect(() => {
    setName(agent.name);
    setApiKey("");
    setAuthJson("");
    setAuthJsonName("");
  }, [agent.id, agent.name]);

  async function loadSettingsAuthJsonFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setAuthJson(await file.text());
    setAuthJsonName(file.name);
  }

  function submitName(event: FormEvent) {
    event.preventDefault();
    if (trimmedName && trimmedName !== agent.name) onSave({ id: agent.id, name: trimmedName });
  }

  function submitCredential(event: FormEvent) {
    event.preventDefault();
    if (agent.authMode === "api" && apiKey.trim()) onRelogin({ id: agent.id, apiKey: apiKey.trim() });
    if (agent.authMode === "auth_json" && authJson.trim()) onRelogin({ id: agent.id, authJson });
  }

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/10" />
        <Dialog.Content className="fixed left-1/2 top-8 z-50 w-[min(860px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl outline-none">
          <Dialog.Title className="sr-only">{agent.name} settings</Dialog.Title>
          <div className="flex items-center justify-between gap-3 border-b border-[#eaebef] px-4 py-3">
            <div className="flex min-w-0 items-center gap-3">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-[#fbfbfc] text-[#555d68]">
                <OpenAILogo size={16} />
              </span>
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold">{agent.name}</div>
                <div className="text-[11px] font-medium uppercase text-[#8a8d96]">{authModeLabel(agent.authMode)}</div>
              </div>
            </div>
            <Dialog.Close className="dialog-close-button" title="Close agent settings">
              <X size={15} />
            </Dialog.Close>
          </div>

          <div className="grid max-h-[calc(100vh-96px)] divide-y divide-[#eaebef] overflow-auto px-4">
            <form className="grid gap-2 py-4" onSubmit={submitName}>
              <div className="text-xs font-semibold text-[#1d1d1f]">Agent name</div>
              <div className="grid items-center gap-2 sm:grid-cols-[minmax(0,1fr)_72px]">
                <input
                  className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                  value={name}
                  maxLength={80}
                  onChange={(event) => setName(event.target.value)}
                />
                <button
                  className="inline-flex h-9 items-center justify-center rounded-md border border-[#dedfe4] bg-white px-3 text-sm font-medium text-[#555d68] transition-colors hover:bg-[#f4f5f7] disabled:cursor-not-allowed disabled:text-[#8a8d96] disabled:hover:bg-white"
                  type="submit"
                  disabled={saving || !trimmedName || trimmedName === agent.name}
                >
                  Save
                </button>
              </div>
            </form>

            {agent.authMode === "subscription" ? (
              <SubscriptionUsageCard
                agent={agent}
                onRefresh={() => onRefreshUsage(agent.id)}
                onRelogin={() => onRelogin(agent.id)}
                refreshing={refreshing}
                relogging={relogging}
              />
            ) : (
              <form className="grid gap-3 py-4" onSubmit={submitCredential}>
                <div>
                  <div className="text-xs font-semibold text-[#1d1d1f]">{agent.authMode === "api" ? "API key" : "auth.json"}</div>
                  <div className="mt-0.5 text-[11px] text-[#686b73]">Saving will run Codex login for this agent.</div>
                </div>
                {agent.authMode === "api" ? (
                  <input
                    className="h-9 rounded-md border border-[#dedfe4] bg-white px-3 text-sm outline-none focus:border-[#9ca3af]"
                    type="password"
                    placeholder="OpenAI API key"
                    value={apiKey}
                    onChange={(event) => setApiKey(event.target.value)}
                  />
                ) : (
                  <div className="grid gap-2">
                    <label className="text-button w-fit cursor-pointer" htmlFor={`agent-auth-json-${agent.id}`}>
                      <Upload size={14} />
                      {authJsonName || "Choose auth.json"}
                      <input id={`agent-auth-json-${agent.id}`} className="sr-only" type="file" accept="application/json,.json" onChange={loadSettingsAuthJsonFile} />
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
                <div className="flex justify-end">
                  <button className="text-button h-9 px-3" type="submit" disabled={relogging || (agent.authMode === "api" ? !apiKey.trim() : !authJson.trim())}>
                    <KeyRound size={14} /> Save credentials
                  </button>
                </div>
              </form>
            )}

            <AgentAssetKindCard
              agent={agent}
              kind="plugins"
              title="Plugin"
              icon={Package}
              assets={assetRegistry.plugins}
              selected={agent.pluginNames ?? []}
              onInstall={onInstallAsset}
              onRemove={onRemoveAsset}
              onAdd={() => onOpenConfig("plugins")}
              pendingAsset={pendingAsset}
            />

            <AgentAssetKindCard
              agent={agent}
              kind="skills"
              title="Skill"
              icon={FileText}
              assets={assetRegistry.skills}
              selected={agent.skillNames ?? []}
              onInstall={onInstallAsset}
              onRemove={onRemoveAsset}
              onAdd={() => onOpenConfig("skills")}
              pendingAsset={pendingAsset}
            />

            <AgentMcpCard
              agent={agent}
              registry={mcpRegistry}
              pending={pendingMcpAgentId === agent.id}
              onSave={(mcpServerNames) => onSave({ id: agent.id, mcpServerNames })}
              onAdd={() => onOpenConfig("mcp")}
            />
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function AgentMcpCard({
  agent,
  registry,
  pending,
  onSave,
  onAdd
}: {
  agent: RegisteredAgentDTO;
  registry: AgentMcpRegistryDTO;
  pending: boolean;
  onSave: (mcpServerNames: string[]) => void;
  onAdd: () => void;
}) {
  const selected = agent.mcpServerNames ?? [];
  const names = Array.from(new Set([...Object.keys(registry.mcpServers), ...selected])).sort();

  return (
    <div className="grid gap-3 py-4 text-xs">
      <SectionHeader icon={Server} title="MCP" count={selected.length} actionLabel="Add MCP" onAction={onAdd} />
      {names.length > 0 ? (
        <div className="grid gap-1">
          {names.map((name) => {
            const installed = selected.includes(name);
            const server = registry.mcpServers[name];
            const nextNames = installed ? selected.filter((item) => item !== name) : [...selected, name];

            return (
              <div key={name} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-t border-[#eaebef] py-2 first:border-t-0">
                <span className="grid min-w-0 gap-0.5">
                  <span className="truncate font-medium text-[#555d68]">{name}</span>
                  <span className="mono truncate text-[11px] text-[#8a8d96]">{server ? mcpCommandPreview(server) : "Definition missing"}</span>
                </span>
                <button
                  className="dialog-close-button"
                  type="button"
                  title={installed ? `Remove ${name}` : `Install ${name}`}
                  aria-label={installed ? `Remove ${name}` : `Install ${name}`}
                  disabled={pending || (!installed && !server)}
                  onClick={() => onSave(nextNames)}
                >
                  {installed ? <Trash2 size={13} /> : <Download size={13} />}
                </button>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="text-xs text-[#686b73]">No MCP server definitions.</div>
      )}
    </div>
  );
}

function AgentAssetKindCard({
  agent,
  kind,
  title,
  icon,
  assets,
  selected,
  onInstall,
  onRemove,
  onAdd,
  pendingAsset
}: {
  agent: RegisteredAgentDTO;
  kind: "skills" | "plugins";
  title: string;
  icon: typeof Package;
  assets: Record<string, AgentAssetDTO>;
  selected: string[];
  onInstall: (input: { id: string; kind: "skills" | "plugins"; name: string }) => void;
  onRemove: (input: { id: string; kind: "skills" | "plugins"; name: string }) => void;
  onAdd: () => void;
  pendingAsset?: { id: string; kind: "skills" | "plugins"; name: string };
}) {
  const names = Object.keys(assets).sort();

  return (
    <div className="grid gap-3 py-4 text-xs">
      <SectionHeader icon={icon} title={title} count={selected.length} actionLabel={`Add ${title}`} onAction={onAdd} />
      {names.length > 0 ? (
        <AgentAssetRows
          agent={agent}
          kind={kind}
          names={names}
          selected={selected}
          assets={assets}
          pendingAsset={pendingAsset}
          onInstall={onInstall}
          onRemove={onRemove}
        />
      ) : (
        <div className="text-xs text-[#686b73]">No {title.toLowerCase()} definitions.</div>
      )}
    </div>
  );
}

function SectionHeader({ icon: Icon, title, count, actionLabel, onAction }: { icon: typeof Package; title: string; count: number; actionLabel: string; onAction: () => void }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <div className="flex min-w-0 items-center gap-2">
        <span className="grid h-7 w-7 shrink-0 place-items-center rounded-md border border-[#dedfe4] bg-[#fbfbfc] text-[#555d68]">
          <Icon size={14} />
        </span>
        <div className="min-w-0">
          <div className="text-sm font-semibold text-[#1d1d1f]">{title}</div>
          <div className="text-[11px] text-[#8a8d96]">{count} installed</div>
        </div>
      </div>
      <button className="text-button shrink-0" type="button" onClick={onAction}>
        <Plus size={13} /> {actionLabel}
      </button>
    </div>
  );
}

function AgentAssetRows({
  agent,
  kind,
  names,
  selected,
  assets,
  pendingAsset,
  onInstall,
  onRemove
}: {
  agent: RegisteredAgentDTO;
  kind: "skills" | "plugins";
  names: string[];
  selected: string[];
  assets: Record<string, AgentAssetDTO>;
  pendingAsset?: { id: string; kind: "skills" | "plugins"; name: string };
  onInstall: (input: { id: string; kind: "skills" | "plugins"; name: string }) => void;
  onRemove: (input: { id: string; kind: "skills" | "plugins"; name: string }) => void;
}) {
  if (names.length === 0) return null;

  return (
    <div className="grid gap-1">
      <div className="text-[11px] font-semibold uppercase text-[#8a8d96]">{kind}</div>
      {names.map((name) => {
        const installed = selected.includes(name);
        const pending = pendingAsset?.id === agent.id && pendingAsset.kind === kind && pendingAsset.name === name;

        return (
          <div key={name} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-t border-[#eaebef] py-2 first:border-t-0">
            <span className="grid min-w-0 gap-0.5">
              <span className="truncate font-medium text-[#555d68]">{name}</span>
              <span className="mono truncate text-[11px] text-[#8a8d96]">{assetSourceLabel(assets[name])}</span>
            </span>
            <button
              className="dialog-close-button"
              type="button"
              title={installed ? `Remove ${name}` : `Install ${name}`}
              aria-label={installed ? `Remove ${name}` : `Install ${name}`}
              disabled={pending}
              onClick={() => (installed ? onRemove({ id: agent.id, kind, name }) : onInstall({ id: agent.id, kind, name }))}
            >
              {installed ? <Trash2 size={13} /> : <Download size={13} />}
            </button>
          </div>
        );
      })}
    </div>
  );
}

function SubscriptionUsageCard({
  agent,
  onRefresh,
  onRelogin,
  refreshing,
  relogging
}: {
  agent: RegisteredAgentDTO;
  onRefresh: () => void;
  onRelogin: () => void;
  refreshing: boolean;
  relogging: boolean;
}) {
  const usage = agent.usage;
  const rateLimits = usage?.rateLimits;
  const title = rateLimits?.limit_name ?? rateLimits?.limit_id ?? "Subscription usage";

  return (
    <div className="grid gap-3 py-4">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="truncate text-xs font-semibold text-[#1d1d1f]">{title}</div>
          <div className="mt-0.5 text-[11px] text-[#8a8d96]">{usageCaption(usage?.status, usage?.checkedAt)}</div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button className="dialog-close-button" type="button" title="Relogin" aria-label={`Relogin ${agent.name}`} onClick={onRelogin} disabled={relogging}>
            <span className="relative block h-4 w-4" aria-hidden="true">
              <KeyRound size={13} className="absolute left-0.5 top-0.5" />
              <RotateCcw size={8} strokeWidth={2.5} className="absolute -right-0.5 -top-0.5" />
            </span>
          </button>
          <button className="dialog-close-button" type="button" title="Refresh usage" onClick={onRefresh} disabled={refreshing}>
            <RefreshCcw size={14} />
          </button>
        </div>
      </div>
      {rateLimits ? (
        <div className="grid gap-2 sm:grid-cols-2">
          <UsageBucket label="Primary" bucket={rateLimits.primary} />
          <UsageBucket label="Secondary" bucket={rateLimits.secondary} />
        </div>
      ) : (
        <div className="text-xs text-[#686b73]">
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

function formatAgentDate(value?: string | null) {
  return value ? new Date(value).toLocaleString() : "n/a";
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

function reloginAgentId(input?: string | { id: string }) {
  return typeof input === "string" ? input : input?.id;
}

function authModeLabel(mode: RegisteredAgentDTO["authMode"]) {
  return mode === "auth_json" ? "auth.json" : mode;
}
