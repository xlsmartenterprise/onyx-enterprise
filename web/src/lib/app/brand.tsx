"use client";

import { useTheme } from "next-themes";
import type { IconProps } from "@opal/types";
import { DEFAULT_APP_NAME, DEFAULT_BRAND_NAME } from "@/lib/constants";
import { cn } from "@opal/utils";

export function BrandLogo({ size = 16, ...props }: IconProps) {
  const { resolvedTheme } = useTheme();

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 64 64"
      xmlns="http://www.w3.org/2000/svg"
      {...props}
    >
      <image
        href={resolvedTheme === "dark" ? "/logo-dark.png" : "/logo.png"}
        width="64"
        height="64"
      />
    </svg>
  );
}

interface BrandWordmarkProps {
  size?: number;
  className?: string;
}

export function BrandWordmark({ size, className }: BrandWordmarkProps) {
  const { resolvedTheme } = useTheme();

  if (DEFAULT_APP_NAME !== DEFAULT_BRAND_NAME) {
    return (
      <span
        className={cn("inline-flex items-center gap-2 text-text-05", className)}
        style={{ fontSize: size }}
      >
        <BrandLogo size={size} />
        <span>{DEFAULT_APP_NAME}</span>
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={resolvedTheme === "dark" ? "/logotype-dark.png" : "/logotype.png"}
      alt=""
      width={560}
      height={128}
      className={className}
      style={size == null ? undefined : { width: (size * 560) / 128, height: size }}
    />
  );
}
