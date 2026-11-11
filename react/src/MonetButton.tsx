import React, {forwardRef, useMemo} from 'react';

import {cx, withVars} from './classes.js';
import type {MonetFamily} from './paint.js';
import {buttonSpec, type MonetButtonKind, type MonetButtonPreset} from './spec.js';
import {useMonetGeometry} from './theme.js';
import {buttonVars} from './vars.js';

type NativeButtonProps = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'children'>;

export interface MonetButtonProps extends NativeButtonProps {
  /** The palette. Defaults to primary. */
  family?: MonetFamily;
  /** Which libmonet button style colours the button. Defaults to `color`. */
  kind?: MonetButtonKind;
  /** Size, edges and corners. Defaults to `regular`. */
  preset?: MonetButtonPreset;
  icon?: React.ReactNode;
  /** Shows the hovered colours while true, as Dart's selected state. */
  selected?: boolean;
  /** Renders a link instead of a button. */
  href?: string;
  children?: React.ReactNode;
}

/** Peer of `MonetButton` (`package:monet_ui/widgets/monet_button.dart`). */
export const MonetButton = forwardRef<HTMLButtonElement & HTMLAnchorElement, MonetButtonProps>(
  function MonetButton(
    {
      family = 'primary',
      kind = 'color',
      preset = 'regular',
      icon,
      selected,
      href,
      className,
      style,
      disabled,
      type = 'button',
      children,
      ...rest
    },
    ref
  ) {
    const geometry = useMonetGeometry();
    const vars = useMemo(
      () => buttonVars(buttonSpec(geometry, {family, kind, preset})),
      [geometry, family, kind, preset]
    );
    const classes = cx(
      'monet-button',
      `monet-button--${preset}`,
      geometry.corner === 'superellipse' && 'monet-superellipse',
      className
    );
    const content = (
      <>
        {icon != null && (
          <span className="monet-button__icon" aria-hidden="true">
            {icon}
          </span>
        )}
        {children != null && <span className="monet-button__label">{children}</span>}
      </>
    );
    const shared = {
      ref,
      className: classes,
      style: withVars(vars, style),
      'data-selected': selected || undefined,
    };
    if (href !== undefined) {
      const anchorProps = rest as unknown as React.AnchorHTMLAttributes<HTMLAnchorElement>;
      return (
        <a
          {...anchorProps}
          {...shared}
          href={disabled ? undefined : href}
          aria-disabled={disabled || undefined}
        >
          {content}
        </a>
      );
    }
    return (
      <button
        {...rest}
        {...shared}
        type={type}
        disabled={disabled}
        aria-pressed={selected}
      >
        {content}
      </button>
    );
  }
);
