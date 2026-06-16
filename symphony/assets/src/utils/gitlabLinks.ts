export function projectAccessTokenUrl(projectWebUrl?: string | null) {
  if (!projectWebUrl) return null;

  const trimmedUrl = projectWebUrl.trim();
  if (!trimmedUrl) return null;

  try {
    const url = new URL(trimmedUrl);
    url.pathname = `${url.pathname.replace(/\/+$/, "")}/-/settings/access_tokens`;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

export function serviceAccountCreateUrl(projectWebUrl?: string | null) {
  const trimmedUrl = projectWebUrl?.trim();
  if (!trimmedUrl) return null;

  try {
    const url = new URL(trimmedUrl);
    url.pathname = "/admin/application_settings/service_accounts";
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}
