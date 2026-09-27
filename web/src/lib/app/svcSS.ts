import type { Metadata } from "next";
import {
  resolveAppName,
  SERVER_SIDE_ONLY__PAID_ENTERPRISE_FEATURES_ENABLED,
} from "@/lib/constants";
import { fetchEnterpriseSettingsSS } from "@/lib/settings/svcSS";

/** Server-side twin of useSettings().appName for server components. */
export async function fetchAppName(): Promise<string> {
  const enterprise = SERVER_SIDE_ONLY__PAID_ENTERPRISE_FEATURES_ENABLED
    ? await fetchEnterpriseSettingsSS()
    : null;
  return resolveAppName(enterprise?.application_name);
}

export async function generateAppMetadata(): Promise<Metadata> {
  const enterprise = SERVER_SIDE_ONLY__PAID_ENTERPRISE_FEATURES_ENABLED
    ? await fetchEnterpriseSettingsSS()
    : null;
  const appName = resolveAppName(enterprise?.application_name);
  const description = `${appName} — Enterprise search and AI assistant.`;
  const icon = enterprise?.use_custom_logo
    ? "/api/enterprise-settings/logo"
    : "/favicon.ico";

  return {
    title: appName,
    description,
    openGraph: { title: appName, description, siteName: appName },
    icons: { icon },
  };
}

export async function generateAdminTitleMetadata(): Promise<Metadata["title"]> {
  return `Admin — ${await fetchAppName()}`;
}
