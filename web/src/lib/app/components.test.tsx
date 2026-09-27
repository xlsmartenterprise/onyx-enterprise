/**
 * @jest-environment jsdom
 */
import { render } from "@testing-library/react";
import { useSettings } from "@/lib/settings/hooks";
import type { AppSettings } from "@/lib/settings/types";
import { Logo } from "@/lib/app/components";

jest.mock("@/lib/settings/hooks", () => ({ useSettings: jest.fn() }));
jest.mock("next-intl", () => ({ useTranslations: () => (key: string) => key }));
jest.mock("next-themes", () => ({
  useTheme: () => ({ resolvedTheme: "light" }),
}));

test("folded name-only branding still shows a recognizable assistant icon", () => {
  jest.mocked(useSettings).mockReturnValue({
    enterprise: {
      application_name: "Partner Portal",
      logo_display_style: "name_only",
    },
    appName: "Partner Portal",
    logoUrl: null,
  } as AppSettings);

  const { container } = render(<Logo folded size={24} />);

  expect(container.querySelector('svg image[href="/logo.png"]')).not.toBeNull();
});
