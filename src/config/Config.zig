/// Config is the main config struct. These fields map directly to the
/// CLI flag names hence we use a lot of `@""` syntax to support hyphens.

// Pandoc is used to automatically generate manual pages and other forms of
// documentation, so documentation comments on fields in the Config struct
// should use Pandoc's flavor of Markdown.
//
// For a reference to Pandoc's Markdown see their [online
// manual.](https://pandoc.org/MANUAL.html#pandocs-markdown)

const Config = @This();

const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const global_state = &@import("../global.zig").state;
const fontpkg = @import("../font/main.zig");
const inputpkg = @import("../input.zig");
const terminal = @import("../terminal/main.zig");
const BackgroundImageProgram = @import("../renderer/opengl/BackgroundImageProgram.zig");
const internal_os = @import("../os/main.zig");
const cli = @import("../cli.zig");
const Command = @import("../Command.zig");

const conditional = @import("conditional.zig");
const Conditional = conditional.Conditional;
const formatterpkg = @import("formatter.zig");
const themepkg = @import("theme.zig");
const url = @import("url.zig");
const Key = @import("key.zig").Key;
const KeyValue = @import("key.zig").Value;
const ErrorList = @import("ErrorList.zig");
const MetricModifier = fontpkg.face.Metrics.Modifier;
const help_strings = @import("help_strings");

const log = std.log.scoped(.config);

/// Used on Unixes for some defaults.
const c = @cImport({
    @cInclude("unistd.h");
});

/// The font families to use.
///
/// You can generate the list of valid values using the CLI:
///
///     ghostty +list-fonts
///
/// This configuration can be repeated multiple times to specify preferred
/// fallback fonts when the requested codepoint is not available in the primary
/// font. This is particularly useful for multiple languages, symbolic fonts,
/// etc.
///
/// Notes on emoji specifically: On macOS, Ghostty by default will always use
/// Apple Color Emoji and on Linux will always use Noto Emoji. You can
/// override this behavior by specifying a font family here that contains
/// emoji glyphs.
///
/// The specific styles (bold, italic, bold italic) do not need to be
/// explicitly set. If a style is not set, then the regular style (font-family)
/// will be searched for stylistic variants. If a stylistic variant is not
/// found, Ghostty will use the regular style. This prevents falling back to a
/// different font family just to get a style such as bold. This also applies
/// if you explicitly specify a font family for a style. For example, if you
/// set `font-family-bold = FooBar` and "FooBar" cannot be found, Ghostty will
/// use whatever font is set for `font-family` for the bold style.
///
/// Finally, some styles may be synthesized if they are not supported.
/// For example, if a font does not have an italic style and no alternative
/// italic font is specified, Ghostty will synthesize an italic style by
/// applying a slant to the regular style. If you want to disable these
/// synthesized styles then you can use the `font-style` configurations
/// as documented below.
///
/// You can disable styles completely by using the `font-style` set of
/// configurations. See the documentation for `font-style` for more information.
///
/// If you want to overwrite a previous set value rather than append a fallback,
/// specify the value as `""` (empty string) to reset the list and then set the
/// new values. For example:
///
///     font-family = ""
///     font-family = "My Favorite Font"
///
/// Setting any of these as CLI arguments will automatically clear the
/// values set in configuration files so you don't need to specify
/// `--font-family=""` before setting a new value. You only need to specify
/// this within config files if you want to clear previously set values in
/// configuration files or on the CLI if you want to clear values set on the
/// CLI.
///
/// Changing this configuration at runtime will only affect new terminals, i.e.
/// new windows, tabs, etc.
@"font-family": RepeatableString = .{},
@"font-family-bold": RepeatableString = .{},
@"font-family-italic": RepeatableString = .{},
@"font-family-bold-italic": RepeatableString = .{},

/// The named font style to use for each of the requested terminal font styles.
/// This looks up the style based on the font style string advertised by the
/// font itself. For example, "Iosevka Heavy" has a style of "Heavy".
///
/// You can also use these fields to completely disable a font style. If you set
/// the value of the configuration below to literal `false` then that font style
/// will be disabled. If the running program in the terminal requests a disabled
/// font style, the regular font style will be used instead.
///
/// These are only valid if its corresponding font-family is also specified. If
/// no font-family is specified, then the font-style is ignored unless you're
/// disabling the font style.
@"font-style": FontStyle = .{ .default = {} },
@"font-style-bold": FontStyle = .{ .default = {} },
@"font-style-italic": FontStyle = .{ .default = {} },
@"font-style-bold-italic": FontStyle = .{ .default = {} },

/// Control whether Ghostty should synthesize a style if the requested style is
/// not available in the specified font-family.
///
/// Ghostty can synthesize bold, italic, and bold italic styles if the font
/// does not have a specific style. For bold, this is done by drawing an
/// outline around the glyph of varying thickness. For italic, this is done by
/// applying a slant to the glyph. For bold italic, both of these are applied.
///
/// Synthetic styles are not perfect and will generally not look as good
/// as a font that has the style natively. However, they are useful to
/// provide styled text when the font does not have the style.
///
/// Set this to "false" or "true" to disable or enable synthetic styles
/// completely. You can disable specific styles using "no-bold", "no-italic",
/// and "no-bold-italic". You can disable multiple styles by separating them
/// with a comma. For example, "no-bold,no-italic".
///
/// Available style keys are: `bold`, `italic`, `bold-italic`.
///
/// If synthetic styles are disabled, then the regular style will be used
/// instead if the requested style is not available. If the font has the
/// requested style, then the font will be used as-is since the style is
/// not synthetic.
///
/// Warning: An easy mistake is to disable `bold` or `italic` but not
/// `bold-italic`. Disabling only `bold` or `italic` will NOT disable either
/// in the `bold-italic` style. If you want to disable `bold-italic`, you must
/// explicitly disable it. You cannot partially disable `bold-italic`.
///
/// By default, synthetic styles are enabled.
@"font-synthetic-style": FontSyntheticStyle = .{},

/// Apply a font feature. This can be repeated multiple times to enable multiple
/// font features. You can NOT set multiple font features with a single value
/// (yet).
///
/// The font feature will apply to all fonts rendered by Ghostty. A future
/// enhancement will allow targeting specific faces.
///
/// A valid value is the name of a feature. Prefix the feature with a `-` to
/// explicitly disable it. Example: `ss20` or `-ss20`.
///
/// To disable programming ligatures, use `-calt` since this is the typical
/// feature name for programming ligatures. To look into what font features
/// your font has and what they do, use a font inspection tool such as
/// [fontdrop.info](https://fontdrop.info).
///
/// To generally disable most ligatures, use `-calt`, `-liga`, and `-dlig` (as
/// separate repetitive entries in your config).
@"font-feature": RepeatableString = .{},

/// Font size in points. This value can be a non-integer and the nearest integer
/// pixel size will be selected. If you have a high dpi display where 1pt = 2px
/// then you can get an odd numbered pixel size by specifying a half point.
///
/// For example, 13.5pt @ 2px/pt = 27px
///
/// Changing this configuration at runtime will only affect new terminals,
/// i.e. new windows, tabs, etc. Note that you may still not see the change
/// depending on your `window-inherit-font-size` setting. If that setting is
/// true, only the first window will be affected by this change since all
/// subsequent windows will inherit the font size of the previous window.
@"font-size": f32 = switch (builtin.os.tag) {
    // On macOS we default a little bigger since this tends to look better. This
    // is purely subjective but this is easy to modify.
    .macos => 13,
    else => 12,
},

/// A repeatable configuration to set one or more font variations values for
/// a variable font. A variable font is a single font, usually with a filename
/// ending in `-VF.ttf` or `-VF.otf` that contains one or more configurable axes
/// for things such as weight, slant, etc. Not all fonts support variations;
/// only fonts that explicitly state they are variable fonts will work.
///
/// The format of this is `id=value` where `id` is the axis identifier. An axis
/// identifier is always a 4 character string, such as `wght`. To get the list
/// of supported axes, look at your font documentation or use a font inspection
/// tool.
///
/// Invalid ids and values are usually ignored. For example, if a font only
/// supports weights from 100 to 700, setting `wght=800` will do nothing (it
/// will not be clamped to 700). You must consult your font's documentation to
/// see what values are supported.
///
/// Common axes are: `wght` (weight), `slnt` (slant), `ital` (italic), `opsz`
/// (optical size), `wdth` (width), `GRAD` (gradient), etc.
@"font-variation": RepeatableFontVariation = .{},
@"font-variation-bold": RepeatableFontVariation = .{},
@"font-variation-italic": RepeatableFontVariation = .{},
@"font-variation-bold-italic": RepeatableFontVariation = .{},

/// Force one or a range of Unicode codepoints to map to a specific named font.
/// This is useful if you want to support special symbols or if you want to use
/// specific glyphs that render better for your specific font.
///
/// The syntax is `codepoint=fontname` where `codepoint` is either a single
/// codepoint or a range. Codepoints must be specified as full Unicode
/// hex values, such as `U+ABCD`. Codepoints ranges are specified as
/// `U+ABCD-U+DEFG`. You can specify multiple ranges for the same font separated
/// by commas, such as `U+ABCD-U+DEFG,U+1234-U+5678=fontname`. The font name is
/// the same value as you would use for `font-family`.
///
/// This configuration can be repeated multiple times to specify multiple
/// codepoint mappings.
///
/// Changing this configuration at runtime will only affect new terminals,
/// i.e. new windows, tabs, etc.
@"font-codepoint-map": RepeatableCodepointMap = .{},

/// Draw fonts with a thicker stroke, if supported. This is only supported
/// currently on macOS.
@"font-thicken": bool = false,

/// All of the configurations behavior adjust various metrics determined by the
/// font. The values can be integers (1, -1, etc.) or a percentage (20%, -15%,
/// etc.). In each case, the values represent the amount to change the original
/// value.
///
/// For example, a value of `1` increases the value by 1; it does not set it to
/// literally 1. A value of `20%` increases the value by 20%. And so on.
///
/// There is little to no validation on these values so the wrong values (i.e.
/// `-100%`) can cause the terminal to be unusable. Use with caution and reason.
///
/// Some values are clamped to minimum or maximum values. This can make it
/// appear that certain values are ignored. For example, many `*-thickness`
/// adjustments cannot go below 1px.
///
/// `adjust-cell-height` has some additional behaviors to describe:
///
///   * The font will be centered vertically in the cell.
///
///   * The cursor will remain the same size as the font, but may be
///     adjusted separately with `adjust-cursor-height`.
///
///   * Powerline glyphs will be adjusted along with the cell height so
///     that things like status lines continue to look aligned.
@"adjust-cell-width": ?MetricModifier = null,
@"adjust-cell-height": ?MetricModifier = null,
/// Distance in pixels from the bottom of the cell to the text baseline.
/// Increase to move baseline UP, decrease to move baseline DOWN.
@"adjust-font-baseline": ?MetricModifier = null,
/// Distance in pixels from the top of the cell to the top of the underline.
/// Increase to move underline DOWN, decrease to move underline UP.
@"adjust-underline-position": ?MetricModifier = null,
/// Thickness in pixels of the underline.
@"adjust-underline-thickness": ?MetricModifier = null,
/// Distance in pixels from the top of the cell to the top of the strikethrough.
/// Increase to move strikethrough DOWN, decrease to move underline UP.
@"adjust-strikethrough-position": ?MetricModifier = null,
/// Thickness in pixels of the strikethrough.
@"adjust-strikethrough-thickness": ?MetricModifier = null,
/// Distance in pixels from the top of the cell to the top of the overline.
/// Increase to move overline DOWN, decrease to move underline UP.
@"adjust-overline-position": ?MetricModifier = null,
/// Thickness in pixels of the overline.
@"adjust-overline-thickness": ?MetricModifier = null,
/// Thickness in pixels of the bar cursor and outlined rect cursor.
@"adjust-cursor-thickness": ?MetricModifier = null,
/// Height in pixels of the cursor. Currently applies to all cursor types:
/// bar, rect, and outlined rect.
@"adjust-cursor-height": ?MetricModifier = null,
/// Thickness in pixels of box drawing characters.
@"adjust-box-thickness": ?MetricModifier = null,

/// The method to use for calculating the cell width of a grapheme cluster.
/// The default value is `unicode` which uses the Unicode standard to determine
/// grapheme width. This results in correct grapheme width but may result in
/// cursor-desync issues with some programs (such as shells) that may use a
/// legacy method such as `wcswidth`.
///
/// Valid values are:
///
/// * `legacy` - Use a legacy method to determine grapheme width, such as
///   wcswidth This maximizes compatibility with legacy programs but may result
///   in incorrect grapheme width for certain graphemes such as skin-tone
///   emoji, non-English characters, etc.
///
///   This is called "legacy" and not something more specific because the
///   behavior is undefined and we want to retain the ability to modify it.
///   For example, we may or may not use libc `wcswidth` now or in the future.
///
/// * `unicode` - Use the Unicode standard to determine grapheme width.
///
/// If a running program explicitly enables terminal mode 2027, then `unicode`
/// width will be forced regardless of this configuration. When mode 2027 is
/// reset, this configuration will be used again.
///
/// This configuration can be changed at runtime but will not affect existing
/// terminals. Only new terminals will use the new configuration.
@"grapheme-width-method": GraphemeWidthMethod = .unicode,

/// FreeType load flags to enable. The format of this is a list of flags to
/// enable separated by commas. If you prefix a flag with `no-` then it is
/// disabled. If you omit a flag, it's default value is used, so you must
/// explicitly disable flags you don't want. You can also use `true` or `false`
/// to turn all flags on or off.
///
/// This configuration only applies to Ghostty builds that use FreeType.
/// This is usually the case only for Linux builds. macOS uses CoreText
/// and does not have an equivalent configuration.
///
/// Available flags:
///
///   * `hinting` - Enable or disable hinting, enabled by default.
///   * `force-autohint` - Use the freetype auto-hinter rather than the
///     font's native hinter. Enabled by default.
///   * `monochrome` - Instructs renderer to use 1-bit monochrome
///     rendering. This option doesn't impact the hinter.
///     Enabled by default.
///   * `autohint` - Use the freetype auto-hinter. Enabled by default.
///
/// Example: `hinting`, `no-hinting`, `force-autohint`, `no-force-autohint`
@"freetype-load-flags": FreetypeLoadFlags = .{},

/// A theme to use. This can be a built-in theme name, a custom theme
/// name, or an absolute path to a custom theme file. Ghostty also supports
/// specifying a different theme to use for light and dark mode. Each
/// option is documented below.
///
/// If the theme is an absolute pathname, Ghostty will attempt to load that
/// file as a theme. If that file does not exist or is inaccessible, an error
/// will be logged and no other directories will be searched.
///
/// If the theme is not an absolute pathname, two different directories will be
/// searched for a file name that matches the theme. This is case sensitive on
/// systems with case-sensitive filesystems. It is an error for a theme name to
/// include path separators unless it is an absolute pathname.
///
/// The first directory is the `themes` subdirectory of your Ghostty
/// configuration directory. This is `$XDG_CONFIG_DIR/ghostty/themes` or
/// `~/.config/ghostty/themes`.
///
/// The second directory is the `themes` subdirectory of the Ghostty resources
/// directory. Ghostty ships with a multitude of themes that will be installed
/// into this directory. On macOS, this list is in the
/// `Ghostty.app/Contents/Resources/ghostty/themes` directory. On Linux, this
/// list is in the `share/ghostty/themes` directory (wherever you installed the
/// Ghostty "share" directory.
///
/// To see a list of available themes, run `ghostty +list-themes`.
///
/// A theme file is simply another Ghostty configuration file. They share
/// the same syntax and same configuration options. A theme can set any valid
/// configuration option so please do not use a theme file from an untrusted
/// source. The built-in themes are audited to only set safe configuration
/// options.
///
/// Some options cannot be set within theme files. The reason these are not
/// supported should be self-evident. A theme file cannot set `theme` or
/// `config-file`. At the time of writing this, Ghostty will not show any
/// warnings or errors if you set these options in a theme file but they will
/// be silently ignored.
///
/// Any additional colors specified via background, foreground, palette, etc.
/// will override the colors specified in the theme.
///
/// To specify a different theme for light and dark mode, use the following
/// syntax: `light:theme-name,dark:theme-name`. For example:
/// `light:rose-pine-dawn,dark:rose-pine`. Whitespace around all values are
/// trimmed and order of light and dark does not matter. Both light and dark
/// must be specified in this form. In this form, the theme used will be
/// based on the current desktop environment theme.
///
/// There are some known bugs with light/dark mode theming. These will
/// be fixed in a future update:
///
///   - macOS: titlebar tabs style is not updated when switching themes.
///
theme: ?Theme = null,

/// Background color for the window.
background: Color = .{ .r = 0x28, .g = 0x2C, .b = 0x34 },

/// Foreground color for the window.
foreground: Color = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF },

/// Background image for the window.
@"background-image": RepeatablePath = .{},

/// Background image opactity
@"background-image-opacity": f32 = 0.0,

/// Background image mode to use.
///
/// `aspect` keeps the aspect-ratio of the background image and `scaled` scales
/// the image to fit the window. `aspect` is the default mode.
///
/// Valid values are:
///
///   * `aspect`
///   * `scaled`
///
@"background-image-mode": BackgroundImageProgram.BackgroundMode = .aspect,

/// The foreground and background color for selection. If this is not set, then
/// the selection color is just the inverted window background and foreground
/// (note: not to be confused with the cell bg/fg).
@"selection-foreground": ?Color = null,
@"selection-background": ?Color = null,

/// Swap the foreground and background colors of cells for selection. This
/// option overrides the `selection-foreground` and `selection-background`
/// options.
///
/// If you select across cells with differing foregrounds and backgrounds, the
/// selection color will vary across the selection.
@"selection-invert-fg-bg": bool = false,

/// The minimum contrast ratio between the foreground and background colors.
/// The contrast ratio is a value between 1 and 21. A value of 1 allows for no
/// contrast (i.e. black on black). This value is the contrast ratio as defined
/// by the [WCAG 2.0 specification](https://www.w3.org/TR/WCAG20/).
///
/// If you want to avoid invisible text (same color as background), a value of
/// 1.1 is a good value. If you want to avoid text that is difficult to read, a
/// value of 3 or higher is a good value. The higher the value, the more likely
/// that text will become black or white.
///
/// This value does not apply to Emoji or images.
@"minimum-contrast": f64 = 1,

/// Color palette for the 256 color form that many terminal applications use.
/// The syntax of this configuration is `N=HEXCODE` where `N` is 0 to 255 (for
/// the 256 colors in the terminal color table) and `HEXCODE` is a typical RGB
/// color code such as `#AABBCC`.
///
/// For definitions on all the codes [see this cheat
/// sheet](https://www.ditig.com/256-colors-cheat-sheet).
palette: Palette = .{},

/// The color of the cursor. If this is not set, a default will be chosen.
@"cursor-color": ?Color = null,

/// Swap the foreground and background colors of the cell under the cursor. This
/// option overrides the `cursor-color` and `cursor-text` options.
@"cursor-invert-fg-bg": bool = false,

/// The opacity level (opposite of transparency) of the cursor. A value of 1
/// is fully opaque and a value of 0 is fully transparent. A value less than 0
/// or greater than 1 will be clamped to the nearest valid value. Note that a
/// sufficiently small value such as 0.3 may be effectively invisible and may
/// make it difficult to find the cursor.
@"cursor-opacity": f64 = 1.0,

/// The style of the cursor. This sets the default style. A running program can
/// still request an explicit cursor style using escape sequences (such as `CSI
/// q`). Shell configurations will often request specific cursor styles.
///
/// Note that shell integration will automatically set the cursor to a bar at
/// a prompt, regardless of this configuration. You can disable that behavior
/// by specifying `shell-integration-features = no-cursor` or disabling shell
/// integration entirely.
///
/// Valid values are:
///
///   * `block`
///   * `bar`
///   * `underline`
///   * `block_hollow`
///
@"cursor-style": terminal.CursorStyle = .block,

/// Sets the default blinking state of the cursor. This is just the default
/// state; running programs may override the cursor style using `DECSCUSR` (`CSI
/// q`).
///
/// If this is not set, the cursor blinks by default. Note that this is not the
/// same as a "true" value, as noted below.
///
/// If this is not set at all (`null`), then Ghostty will respect DEC Mode 12
/// (AT&T cursor blink) as an alternate approach to turning blinking on/off. If
/// this is set to any value other than null, DEC mode 12 will be ignored but
/// `DECSCUSR` will still be respected.
///
/// Valid values are:
///
///   * `` (blank)
///   * `true`
///   * `false`
///
@"cursor-style-blink": ?bool = null,

/// The color of the text under the cursor. If this is not set, a default will
/// be chosen.
@"cursor-text": ?Color = null,

/// Enables the ability to move the cursor at prompts by using `alt+click` on
/// Linux and `option+click` on macOS.
///
/// This feature requires shell integration (specifically prompt marking
/// via `OSC 133`) and only works in primary screen mode. Alternate screen
/// applications like vim usually have their own version of this feature but
/// this configuration doesn't control that.
///
/// It should be noted that this feature works by translating your desired
/// position into a series of synthetic arrow key movements, so some weird
/// behavior around edge cases are to be expected. This is unfortunately how
/// this feature is implemented across terminals because there isn't any other
/// way to implement it.
@"cursor-click-to-move": bool = true,

/// Hide the mouse immediately when typing. The mouse becomes visible again
/// when the mouse is used (button, movement, etc.). Platform-specific behavior
/// may dictate other scenarios where the mouse is shown. For example on macOS,
/// the mouse is shown again when a new window, tab, or split is created.
@"mouse-hide-while-typing": bool = false,

/// Determines whether running programs can detect the shift key pressed with a
/// mouse click. Typically, the shift key is used to extend mouse selection.
///
/// The default value of `false` means that the shift key is not sent with
/// the mouse protocol and will extend the selection. This value can be
/// conditionally overridden by the running program with the `XTSHIFTESCAPE`
/// sequence.
///
/// The value `true` means that the shift key is sent with the mouse protocol
/// but the running program can override this behavior with `XTSHIFTESCAPE`.
///
/// The value `never` is the same as `false` but the running program cannot
/// override this behavior with `XTSHIFTESCAPE`. The value `always` is the
/// same as `true` but the running program cannot override this behavior with
/// `XTSHIFTESCAPE`.
///
/// If you always want shift to extend mouse selection even if the program
/// requests otherwise, set this to `never`.
///
/// Valid values are:
///
///   * `true`
///   * `false`
///   * `always`
///   * `never`
///
@"mouse-shift-capture": MouseShiftCapture = .false,

/// Multiplier for scrolling distance with the mouse wheel. Any value less
/// than 0.01 or greater than 10,000 will be clamped to the nearest valid
/// value.
///
/// A value of "1" (default) scrolls te default amount. A value of "2" scrolls
/// double the default amount. A value of "0.5" scrolls half the default amount.
/// Et cetera.
@"mouse-scroll-multiplier": f64 = 1.0,

/// The opacity level (opposite of transparency) of the background. A value of
/// 1 is fully opaque and a value of 0 is fully transparent. A value less than 0
/// or greater than 1 will be clamped to the nearest valid value.
///
/// On macOS, background opacity is disabled when the terminal enters native
/// fullscreen. This is because the background becomes gray and it can cause
/// widgets to show through which isn't generally desirable.
@"background-opacity": f64 = 1.0,

/// A positive value enables blurring of the background when background-opacity
/// is less than 1. The value is the blur radius to apply. A value of 20
/// is reasonable for a good looking blur. Higher values will cause strange
/// rendering issues as well as performance issues.
///
/// This is only supported on macOS.
@"background-blur-radius": u8 = 0,

/// The opacity level (opposite of transparency) of an unfocused split.
/// Unfocused splits by default are slightly faded out to make it easier to see
/// which split is focused. To disable this feature, set this value to 1.
///
/// A value of 1 is fully opaque and a value of 0 is fully transparent. Because
/// "0" is not useful (it makes the window look very weird), the minimum value
/// is 0.15. This value still looks weird but you can at least see what's going
/// on. A value outside of the range 0.15 to 1 will be clamped to the nearest
/// valid value.
@"unfocused-split-opacity": f64 = 0.7,

/// The color to dim the unfocused split. Unfocused splits are dimmed by
/// rendering a semi-transparent rectangle over the split. This sets the color of
/// that rectangle and can be used to carefully control the dimming effect.
///
/// This will default to the background color.
@"unfocused-split-fill": ?Color = null,

/// The command to run, usually a shell. If this is not an absolute path, it'll
/// be looked up in the `PATH`. If this is not set, a default will be looked up
/// from your system. The rules for the default lookup are:
///
///   * `SHELL` environment variable
///
///   * `passwd` entry (user information)
///
/// This can contain additional arguments to run the command with. If additional
/// arguments are provided, the command will be executed using `/bin/sh -c`.
/// Ghostty does not do any shell command parsing.
///
/// This command will be used for all new terminal surfaces, i.e. new windows,
/// tabs, etc. If you want to run a command only for the first terminal surface
/// created when Ghostty starts, use the `initial-command` configuration.
///
/// Ghostty supports the common `-e` flag for executing a command with
/// arguments. For example, `ghostty -e fish --with --custom --args`.
/// This flag sets the `initial-command` configuration, see that for more
/// information.
command: ?[]const u8 = null,

/// This is the same as "command", but only applies to the first terminal
/// surface created when Ghostty starts. Subsequent terminal surfaces will use
/// the `command` configuration.
///
/// After the first terminal surface is created (or closed), there is no
/// way to run this initial command again automatically. As such, setting
/// this at runtime works but will only affect the next terminal surface
/// if it is the first one ever created.
///
/// If you're using the `ghostty` CLI there is also a shortcut to set this
/// with arguments directly: you can use the `-e` flag. For example: `ghostty -e
/// fish --with --custom --args`. The `-e` flag automatically forces some
/// other behaviors as well:
///
///   * `gtk-single-instance=false` - This ensures that a new instance is
///     launched and the CLI args are respected.
///
///   * `quit-after-last-window-closed=true` - This ensures that the Ghostty
///     process will exit when the command exits. Additionally, the
///     `quit-after-last-window-closed-delay` is unset.
///
///   * `shell-integration=detect` (if not `none`) - This prevents forcibly
///     injecting any configured shell integration into the command's
///     environment. With `-e` its highly unlikely that you're executing a
///     shell and forced shell integration is likely to cause problems
///     (i.e. by wrapping your command in a shell, setting env vars, etc.).
///     This is a safety measure to prevent unexpected behavior. If you want
///     shell integration with a `-e`-executed command, you must either
///     name your binary appropriately or source the shell integration script
///     manually.
///
@"initial-command": ?[]const u8 = null,

/// If true, keep the terminal open after the command exits. Normally, the
/// terminal window closes when the running command (such as a shell) exits.
/// With this true, the terminal window will stay open until any keypress is
/// received.
///
/// This is primarily useful for scripts or debugging.
@"wait-after-command": bool = false,

/// The number of milliseconds of runtime below which we consider a process exit
/// to be abnormal. This is used to show an error message when the process exits
/// too quickly.
///
/// On Linux, this must be paired with a non-zero exit code. On macOS, we allow
/// any exit code because of the way shell processes are launched via the login
/// command.
@"abnormal-command-exit-runtime": u32 = 250,

/// The size of the scrollback buffer in bytes. This also includes the active
/// screen. No matter what this is set to, enough memory will always be
/// allocated for the visible screen and anything leftover is the limit for
/// the scrollback.
///
/// When this limit is reached, the oldest lines are removed from the
/// scrollback.
///
/// Scrollback currently exists completely in memory. This means that the
/// larger this value, the larger potential memory usage. Scrollback is
/// allocated lazily up to this limit, so if you set this to a very large
/// value, it will not immediately consume a lot of memory.
///
/// This size is per terminal surface, not for the entire application.
///
/// It is not currently possible to set an unlimited scrollback buffer.
/// This is a future planned feature.
///
/// This can be changed at runtime but will only affect new terminal surfaces.
@"scrollback-limit": u32 = 10_000_000, // 10MB

/// Match a regular expression against the terminal text and associate clicking
/// it with an action. This can be used to match URLs, file paths, etc. Actions
/// can be opening using the system opener (i.e. `open` or `xdg-open`) or
/// executing any arbitrary binding action.
///
/// Links that are configured earlier take precedence over links that are
/// configured later.
///
/// A default link that matches a URL and opens it in the system opener always
/// exists. This can be disabled using `link-url`.
///
/// TODO: This can't currently be set!
link: RepeatableLink = .{},

/// Enable URL matching. URLs are matched on hover with control (Linux) or
/// super (macOS) pressed and open using the default system application for
/// the linked URL.
///
/// The URL matcher is always lowest priority of any configured links (see
/// `link`). If you want to customize URL matching, use `link` and disable this.
@"link-url": bool = true,

/// Start new windows in fullscreen. This setting applies to new windows and
/// does not apply to tabs, splits, etc. However, this setting will apply to all
/// new windows, not just the first one.
///
/// On macOS, this setting does not work if window-decoration is set to
/// "false", because native fullscreen on macOS requires window decorations
/// to be set.
fullscreen: bool = false,

/// The title Ghostty will use for the window. This will force the title of the
/// window to be this title at all times and Ghostty will ignore any set title
/// escape sequences programs (such as Neovim) may send.
///
/// If you want a blank title, set this to one or more spaces by quoting
/// the value. For example, `title = " "`. This effectively hides the title.
/// This is necessary because setting a blank value resets the title to the
/// default value of the running program.
///
/// This configuration can be reloaded at runtime. If it is set, the title
/// will update for all windows. If it is unset, the next title change escape
/// sequence will be honored but previous changes will not retroactively
/// be set. This latter case may require you restart programs such as neovim
/// to get the new title.
title: ?[:0]const u8 = null,

/// The setting that will change the application class value.
///
/// This controls the class field of the `WM_CLASS` X11 property (when running
/// under X11), and the Wayland application ID (when running under Wayland).
///
/// Note that changing this value between invocations will create new, separate
/// instances, of Ghostty when running with `gtk-single-instance=true`. See that
/// option for more details.
///
/// The class name must follow the requirements defined [in the GTK
/// documentation](https://docs.gtk.org/gio/type_func.Application.id_is_valid.html).
///
/// The default is `com.mitchellh.ghostty`.
///
/// This only affects GTK builds.
class: ?[:0]const u8 = null,

/// This controls the instance name field of the `WM_CLASS` X11 property when
/// running under X11. It has no effect otherwise.
///
/// The default is `ghostty`.
///
/// This only affects GTK builds.
@"x11-instance-name": ?[:0]const u8 = null,

/// The directory to change to after starting the command.
///
/// This setting is secondary to the `window-inherit-working-directory`
/// setting. If a previous Ghostty terminal exists in the same process,
/// `window-inherit-working-directory` will take precedence. Otherwise, this
/// setting will be used. Typically, this setting is used only for the first
/// window.
///
/// The default is `inherit` except in special scenarios listed next. On macOS,
/// if Ghostty can detect it is launched from launchd (double-clicked) or
/// `open`, then it defaults to `home`. On Linux with GTK, if Ghostty can detect
/// it was launched from a desktop launcher, then it defaults to `home`.
///
/// The value of this must be an absolute value or one of the special values
/// below:
///
///   * `home` - The home directory of the executing user.
///
///   * `inherit` - The working directory of the launching process.
@"working-directory": ?[]const u8 = null,

/// Key bindings. The format is `trigger=action`. Duplicate triggers will
/// overwrite previously set values. The list of actions is available in
/// the documentation or using the `ghostty +list-actions` command.
///
/// Trigger: `+`-separated list of keys and modifiers. Example: `ctrl+a`,
/// `ctrl+shift+b`, `up`. Some notes:
///
///   * modifiers cannot repeat, `ctrl+ctrl+a` is invalid.
///
///   * modifiers and keys can be in any order, `shift+a+ctrl` is *weird*,
///     but valid.
///
///   * only a single key input is allowed, `ctrl+a+b` is invalid.
///
///   * the key input can be prefixed with `physical:` to specify a
///     physical key mapping rather than a logical one. A physical key
///     mapping responds to the hardware keycode and not the keycode
///     translated by any system keyboard layouts. Example: "ctrl+physical:a"
///
/// Valid modifiers are `shift`, `ctrl` (alias: `control`), `alt` (alias: `opt`,
/// `option`), and `super` (alias: `cmd`, `command`). You may use the modifier
/// or the alias. When debugging keybinds, the non-aliased modifier will always
/// be used in output.
///
/// Note: The fn or "globe" key on keyboards are not supported as a
/// modifier. This is a limitation of the operating systems and GUI toolkits
/// that Ghostty uses.
///
/// You may also specify multiple triggers separated by `>` to require a
/// sequence of triggers to activate the action. For example,
/// `ctrl+a>n=new_window` will only trigger the `new_window` action if the
/// user presses `ctrl+a` followed separately by `n`. In other software, this
/// is sometimes called a leader key, a key chord, a key table, etc. There
/// is no hardcoded limit on the number of parts in a sequence.
///
/// Warning: If you define a sequence as a CLI argument to `ghostty`,
/// you probably have to quote the keybind since `>` is a special character
/// in most shells. Example: ghostty --keybind='ctrl+a>n=new_window'
///
/// A trigger sequence has some special handling:
///
///   * Ghostty will wait an indefinite amount of time for the next key in
///     the sequence. There is no way to specify a timeout. The only way to
///     force the output of a prefix key is to assign another keybind to
///     specifically output that key (i.e. `ctrl+a>ctrl+a=text:foo`) or
///     press an unbound key which will send both keys to the program.
///
///   * If a prefix in a sequence is previously bound, the sequence will
///     override the previous binding. For example, if `ctrl+a` is bound to
///     `new_window` and `ctrl+a>n` is bound to `new_tab`, pressing `ctrl+a`
///     will do nothing.
///
///   * Adding to the above, if a previously bound sequence prefix is
///     used in a new, non-sequence binding, the entire previously bound
///     sequence will be unbound. For example, if you bind `ctrl+a>n` and
///     `ctrl+a>t`, and then bind `ctrl+a` directly, both `ctrl+a>n` and
///     `ctrl+a>t` will become unbound.
///
///   * Trigger sequences are not allowed for `global:` or `all:`-prefixed
///     triggers. This is a limitation we could remove in the future.
///
/// Action is the action to take when the trigger is satisfied. It takes the
/// format `action` or `action:param`. The latter form is only valid if the
/// action requires a parameter.
///
///   * `ignore` - Do nothing, ignore the key input. This can be used to
///     black hole certain inputs to have no effect.
///
///   * `unbind` - Remove the binding. This makes it so the previous action
///     is removed, and the key will be sent through to the child command
///     if it is printable.
///
///   * `csi:text` - Send a CSI sequence. i.e. `csi:A` sends "cursor up".
///
///   * `esc:text` - Send an escape sequence. i.e. `esc:d` deletes to the
///     end of the word to the right.
///
///   * `text:text` - Send a string. Uses Zig string literal syntax.
///     i.e. `text:\x15` sends Ctrl-U.
///
///   * All other actions can be found in the documentation or by using the
///     `ghostty +list-actions` command.
///
/// Some notes for the action:
///
///   * The parameter is taken as-is after the `:`. Double quotes or
///     other mechanisms are included and NOT parsed. If you want to
///     send a string value that includes spaces, wrap the entire
///     trigger/action in double quotes. Example: `--keybind="up=csi:A B"`
///
/// There are some additional special values that can be specified for
/// keybind:
///
///   * `keybind=clear` will clear all set keybindings. Warning: this
///     removes ALL keybindings up to this point, including the default
///     keybindings.
///
/// The keybind trigger can be prefixed with some special values to change
/// the behavior of the keybind. These are:
///
///   * `all:` - Make the keybind apply to all terminal surfaces. By default,
///     keybinds only apply to the focused terminal surface. If this is true,
///     then the keybind will be sent to all terminal surfaces. This only
///     applies to actions that are surface-specific. For actions that
///     are already global (i.e. `quit`), this prefix has no effect.
///
///   * `global:` - Make the keybind global. By default, keybinds only work
///     within Ghostty and under the right conditions (application focused,
///     sometimes terminal focused, etc.). If you want a keybind to work
///     globally across your system (i.e. even when Ghostty is not focused),
///     specify this prefix. This prefix implies `all:`. Note: this does not
///     work in all environments; see the additional notes below for more
///     information.
///
///   * `unconsumed:` - Do not consume the input. By default, a keybind
///     will consume the input, meaning that the associated encoding (if
///     any) will not be sent to the running program in the terminal. If
///     you wish to send the encoded value to the program, specify the
///     `unconsumed:` prefix before the entire keybind. For example:
///     `unconsumed:ctrl+a=reload_config`. `global:` and `all:`-prefixed
///     keybinds will always consume the input regardless of this setting.
///     Since they are not associated with a specific terminal surface,
///     they're never encoded.
///
/// Keybind triggers are not unique per prefix combination. For example,
/// `ctrl+a` and `global:ctrl+a` are not two separate keybinds. The keybind
/// set later will overwrite the keybind set earlier. In this case, the
/// `global:` keybind will be used.
///
/// Multiple prefixes can be specified. For example,
/// `global:unconsumed:ctrl+a=reload_config` will make the keybind global
/// and not consume the input to reload the config.
///
/// Note: `global:` is only supported on macOS. On macOS,
/// this feature requires accessibility permissions to be granted to Ghostty.
/// When a `global:` keybind is specified and Ghostty is launched or reloaded,
/// Ghostty will attempt to request these permissions. If the permissions are
/// not granted, the keybind will not work. On macOS, you can find these
/// permissions in System Preferences -> Privacy & Security -> Accessibility.
keybind: Keybinds = .{},

/// Horizontal window padding. This applies padding between the terminal cells
/// and the left and right window borders. The value is in points, meaning that
/// it will be scaled appropriately for screen DPI.
///
/// If this value is set too large, the screen will render nothing, because the
/// grid will be completely squished by the padding. It is up to you as the user
/// to pick a reasonable value. If you pick an unreasonable value, a warning
/// will appear in the logs.
///
/// Changing this configuration at runtime will only affect new terminals, i.e.
/// new windows, tabs, etc.
///
/// To set a different left and right padding, specify two numerical values
/// separated by a comma. For example, `window-padding-x = 2,4` will set the
/// left padding to 2 and the right padding to 4. If you want to set both
/// paddings to the same value, you can use a single value. For example,
/// `window-padding-x = 2` will set both paddings to 2.
@"window-padding-x": WindowPadding = .{ .top_left = 2, .bottom_right = 2 },

/// Vertical window padding. This applies padding between the terminal cells and
/// the top and bottom window borders. The value is in points, meaning that it
/// will be scaled appropriately for screen DPI.
///
/// If this value is set too large, the screen will render nothing, because the
/// grid will be completely squished by the padding. It is up to you as the user
/// to pick a reasonable value. If you pick an unreasonable value, a warning
/// will appear in the logs.
///
/// Changing this configuration at runtime will only affect new terminals,
/// i.e. new windows, tabs, etc.
///
/// To set a different top and bottom padding, specify two numerical values
/// separated by a comma. For example, `window-padding-y = 2,4` will set the
/// top padding to 2 and the bottom padding to 4. If you want to set both
/// paddings to the same value, you can use a single value. For example,
/// `window-padding-y = 2` will set both paddings to 2.
@"window-padding-y": WindowPadding = .{ .top_left = 2, .bottom_right = 2 },

/// The viewport dimensions are usually not perfectly divisible by the cell
/// size. In this case, some extra padding on the end of a column and the bottom
/// of the final row may exist. If this is `true`, then this extra padding
/// is automatically balanced between all four edges to minimize imbalance on
/// one side. If this is `false`, the top left grid cell will always hug the
/// edge with zero padding other than what may be specified with the other
/// `window-padding` options.
///
/// If other `window-padding` fields are set and this is `true`, this will still
/// apply. The other padding is applied first and may affect how many grid cells
/// actually exist, and this is applied last in order to balance the padding
/// given a certain viewport size and grid cell size.
@"window-padding-balance": bool = false,

/// The color of the padding area of the window. Valid values are:
///
/// * `background` - The background color specified in `background`.
/// * `extend` - Extend the background color of the nearest grid cell.
/// * `extend-always` - Same as "extend" but always extends without applying
///   any of the heuristics that disable extending noted below.
///
/// The "extend" value will be disabled in certain scenarios. On primary
/// screen applications (i.e. not something like Neovim), the color will not
/// be extended vertically if any of the following are true:
///
/// * The nearest row has any cells that have the default background color.
///   The thinking is that in this case, the default background color looks
///   fine as a padding color.
/// * The nearest row is a prompt row (requires shell integration). The
///   thinking here is that prompts often contain powerline glyphs that
///   do not look good extended.
/// * The nearest row contains a perfect fit powerline character. These
///   don't look good extended.
///
@"window-padding-color": WindowPaddingColor = .background,

/// Synchronize rendering with the screen refresh rate. If true, this will
/// minimize tearing and align redraws with the screen but may cause input
/// latency. If false, this will maximize redraw frequency but may cause tearing,
/// and under heavy load may use more CPU and power.
///
/// This defaults to true because out-of-sync rendering on macOS can
/// cause kernel panics (macOS 14.4+) and performance issues for external
/// displays over some hardware such as DisplayLink. If you want to minimize
/// input latency, set this to false with the known aforementioned risks.
///
/// Changing this value at runtime will only affect new terminals.
///
/// This setting is only supported currently on macOS.
@"window-vsync": bool = true,

/// If true, new windows and tabs will inherit the working directory of the
/// previously focused window. If no window was previously focused, the default
/// working directory will be used (the `working-directory` option).
@"window-inherit-working-directory": bool = true,

/// If true, new windows and tabs will inherit the font size of the previously
/// focused window. If no window was previously focused, the default font size
/// will be used. If this is false, the default font size specified in the
/// configuration `font-size` will be used.
@"window-inherit-font-size": bool = true,

/// Valid values:
///
///   * `true`
///   * `false` - windows won't have native decorations, i.e. titlebar and
///      borders. On macOS this also disables tabs and tab overview.
///
/// The "toggle_window_decorations" keybind action can be used to create
/// a keybinding to toggle this setting at runtime.
///
/// Changing this configuration in your configuration and reloading will
/// only affect new windows. Existing windows will not be affected.
///
/// macOS: To hide the titlebar without removing the native window borders
///        or rounded corners, use `macos-titlebar-style = hidden` instead.
@"window-decoration": bool = true,

/// The font that will be used for the application's window and tab titles.
///
/// This is currently only supported on macOS.
@"window-title-font-family": ?[:0]const u8 = null,

/// The theme to use for the windows. Valid values:
///
///   * `auto` - Determine the theme based on the configured terminal
///      background color. This has no effect if the "theme" configuration
///      has separate light and dark themes. In that case, the behavior
///      of "auto" is equivalent to "system".
///   * `system` - Use the system theme.
///   * `light` - Use the light theme regardless of system theme.
///   * `dark` - Use the dark theme regardless of system theme.
///   * `ghostty` - Use the background and foreground colors specified in the
///     Ghostty configuration. This is only supported on Linux builds with
///     Adwaita and `gtk-adwaita` enabled.
///
/// On macOS, if `macos-titlebar-style` is "tabs", the window theme will be
/// automatically set based on the luminosity of the terminal background color.
/// This only applies to terminal windows. This setting will still apply to
/// non-terminal windows within Ghostty.
///
/// This is currently only supported on macOS and Linux.
@"window-theme": WindowTheme = .auto,

/// The colorspace to use for the terminal window. The default is `srgb` but
/// this can also be set to `display-p3` to use the Display P3 colorspace.
///
/// Changing this value at runtime will only affect new windows.
///
/// This setting is only supported on macOS.
@"window-colorspace": WindowColorspace = .srgb,

/// The initial window size. This size is in terminal grid cells by default.
/// Both values must be set to take effect. If only one value is set, it is
/// ignored.
///
/// We don't currently support specifying a size in pixels but a future change
/// can enable that. If this isn't specified, the app runtime will determine
/// some default size.
///
/// Note that the window manager may put limits on the size or override the
/// size. For example, a tiling window manager may force the window to be a
/// certain size to fit within the grid. There is nothing Ghostty will do about
/// this, but it will make an effort.
///
/// Sizes larger than the screen size will be clamped to the screen size.
/// This can be used to create a maximized-by-default window size.
///
/// This will not affect new tabs, splits, or other nested terminal elements.
/// This only affects the initial window size of any new window. Changing this
/// value will not affect the size of the window after it has been created. This
/// is only used for the initial size.
///
/// BUG: On Linux with GTK, the calculated window size will not properly take
/// into account window decorations. As a result, the grid dimensions will not
/// exactly match this configuration. If window decorations are disabled (see
/// window-decorations), then this will work as expected.
///
/// Windows smaller than 10 wide by 4 high are not allowed.
@"window-height": u32 = 0,
@"window-width": u32 = 0,

/// Whether to enable saving and restoring window state. Window state includes
/// their position, size, tabs, splits, etc. Some window state requires shell
/// integration, such as preserving working directories. See `shell-integration`
/// for more information.
///
/// There are three valid values for this configuration:
///
///   * `default` will use the default system behavior. On macOS, this
///     will only save state if the application is forcibly terminated
///     or if it is configured systemwide via Settings.app.
///
///   * `never` will never save window state.
///
///   * `always` will always save window state whenever Ghostty is exited.
///
/// If you change this value to `never` while Ghostty is not running, the next
/// Ghostty launch will NOT restore the window state.
///
/// If you change this value to `default` while Ghostty is not running and the
/// previous exit saved state, the next Ghostty launch will still restore the
/// window state. This is because Ghostty cannot know if the previous exit was
/// due to a forced save or not (macOS doesn't provide this information).
///
/// If you change this value so that window state is saved while Ghostty is not
/// running, the previous window state will not be restored because Ghostty only
/// saves state on exit if this is enabled.
///
/// The default value is `default`.
///
/// This is currently only supported on macOS. This has no effect on Linux.
@"window-save-state": WindowSaveState = .default,

/// Resize the window in discrete increments of the focused surface's cell size.
/// If this is disabled, surfaces are resized in pixel increments. Currently
/// only supported on macOS.
@"window-step-resize": bool = false,

/// The position where new tabs are created. Valid values:
///
///   * `current` - Insert the new tab after the currently focused tab,
///     or at the end if there are no focused tabs.
///
///   * `end` - Insert the new tab at the end of the tab list.
@"window-new-tab-position": WindowNewTabPosition = .current,

/// This controls when resize overlays are shown. Resize overlays are a
/// transient popup that shows the size of the terminal while the surfaces are
/// being resized. The possible options are:
///
///   * `always` - Always show resize overlays.
///   * `never` - Never show resize overlays.
///   * `after-first` - The resize overlay will not appear when the surface
///                     is first created, but will show up if the surface is
///                     subsequently resized.
///
/// The default is `after-first`.
@"resize-overlay": ResizeOverlay = .@"after-first",

/// If resize overlays are enabled, this controls the position of the overlay.
/// The possible options are:
///
///   * `center`
///   * `top-left`
///   * `top-center`
///   * `top-right`
///   * `bottom-left`
///   * `bottom-center`
///   * `bottom-right`
///
/// The default is `center`.
@"resize-overlay-position": ResizeOverlayPosition = .center,

/// If resize overlays are enabled, this controls how long the overlay is
/// visible on the screen before it is hidden. The default is ¾ of a second or
/// 750 ms.
///
/// The duration is specified as a series of numbers followed by time units.
/// Whitespace is allowed between numbers and units. Each number and unit will
/// be added together to form the total duration.
///
/// The allowed time units are as follows:
///
///   * `y` - 365 SI days, or 8760 hours, or 31536000 seconds. No adjustments
///     are made for leap years or leap seconds.
///   * `d` - one SI day, or 86400 seconds.
///   * `h` - one hour, or 3600 seconds.
///   * `m` - one minute, or 60 seconds.
///   * `s` - one second.
///   * `ms` - one millisecond, or 0.001 second.
///   * `us` or `µs` - one microsecond, or 0.000001 second.
///   * `ns` - one nanosecond, or 0.000000001 second.
///
/// Examples:
///   * `1h30m`
///   * `45s`
///
/// Units can be repeated and will be added together. This means that
/// `1h1h` is equivalent to `2h`. This is confusing and should be avoided.
/// A future update may disallow this.
///
/// The maximum value is `584y 49w 23h 34m 33s 709ms 551µs 615ns`. Any
/// value larger than this will be clamped to the maximum value.
@"resize-overlay-duration": Duration = .{ .duration = 750 * std.time.ns_per_ms },

/// If true, when there are multiple split panes, the mouse selects the pane
/// that is focused. This only applies to the currently focused window; i.e.
/// mousing over a split in an unfocused window will now focus that split
/// and bring the window to front.
///
/// Default is false.
@"focus-follows-mouse": bool = false,

/// Whether to allow programs running in the terminal to read/write to the
/// system clipboard (OSC 52, for googling). The default is to allow clipboard
/// reading after prompting the user and allow writing unconditionally.
///
/// Valid values are:
///
///   * `ask`
///   * `allow`
///   * `deny`
///
@"clipboard-read": ClipboardAccess = .ask,
@"clipboard-write": ClipboardAccess = .allow,

/// Trims trailing whitespace on data that is copied to the clipboard. This does
/// not affect data sent to the clipboard via `clipboard-write`.
@"clipboard-trim-trailing-spaces": bool = true,

/// Require confirmation before pasting text that appears unsafe. This helps
/// prevent a "copy/paste attack" where a user may accidentally execute unsafe
/// commands by pasting text with newlines.
@"clipboard-paste-protection": bool = true,

/// If true, bracketed pastes will be considered safe. By default, bracketed
/// pastes are considered safe. "Bracketed" pastes are pastes while the running
/// program has bracketed paste mode enabled (a setting set by the running
/// program, not the terminal emulator).
@"clipboard-paste-bracketed-safe": bool = true,

/// The total amount of bytes that can be used for image data (i.e. the Kitty
/// image protocol) per terminal screen. The maximum value is 4,294,967,295
/// (4GiB). The default is 320MB. If this is set to zero, then all image
/// protocols will be disabled.
///
/// This value is separate for primary and alternate screens so the effective
/// limit per surface is double.
@"image-storage-limit": u32 = 320 * 1000 * 1000,

/// Whether to automatically copy selected text to the clipboard. `true`
/// will prefer to copy to the selection clipboard if supported by the
/// OS, otherwise it will copy to the system clipboard.
///
/// The value `clipboard` will always copy text to the selection clipboard
/// (for supported systems) as well as the system clipboard. This is sometimes
/// a preferred behavior on Linux.
///
/// Middle-click paste will always use the selection clipboard on Linux
/// and the system clipboard on macOS. Middle-click paste is always enabled
/// even if this is `false`.
///
/// The default value is true on Linux and false on macOS. macOS copy on
/// select behavior is not typical for applications so it is disabled by
/// default. On Linux, this is a standard behavior so it is enabled by
/// default.
@"copy-on-select": CopyOnSelect = switch (builtin.os.tag) {
    .linux => .true,
    .macos => .false,
    else => .false,
},

/// The time in milliseconds between clicks to consider a click a repeat
/// (double, triple, etc.) or an entirely new single click. A value of zero will
/// use a platform-specific default. The default on macOS is determined by the
/// OS settings. On every other platform it is 500ms.
@"click-repeat-interval": u32 = 0,

/// Additional configuration files to read. This configuration can be repeated
/// to read multiple configuration files. Configuration files themselves can
/// load more configuration files. Paths are relative to the file containing the
/// `config-file` directive. For command-line arguments, paths are relative to
/// the current working directory.
///
/// Prepend a ? character to the file path to suppress errors if the file does
/// not exist. If you want to include a file that begins with a literal ?
/// character, surround the file path in double quotes (").
///
/// Cycles are not allowed. If a cycle is detected, an error will be logged and
/// the configuration file will be ignored.
///
/// Configuration files are loaded after the configuration they're defined
/// within in the order they're defined. **THIS IS A VERY SUBTLE BUT IMPORTANT
/// POINT.** To put it another way: configuration files do not take effect
/// until after the entire configuration is loaded. For example, in the
/// configuration below:
///
/// ```
/// config-file = "foo"
/// a = 1
/// ```
///
/// If "foo" contains `a = 2`, the final value of `a` will be 2, because
/// `foo` is loaded after the configuration file that configures the
/// nested `config-file` value.
@"config-file": RepeatablePath = .{},

/// When this is true, the default configuration file paths will be loaded.
/// The default configuration file paths are currently only the XDG
/// config path ($XDG_CONFIG_HOME/ghostty/config).
///
/// If this is false, the default configuration paths will not be loaded.
/// This is targeted directly at using Ghostty from the CLI in a way
/// that minimizes external effects.
///
/// This is a CLI-only configuration. Setting this in a configuration file
/// will have no effect. It is not an error, but it will not do anything.
/// This configuration can only be set via CLI arguments.
@"config-default-files": bool = true,

/// Confirms that a surface should be closed before closing it. This defaults to
/// true. If set to false, surfaces will close without any confirmation.
@"confirm-close-surface": bool = true,

/// Whether or not to quit after the last surface is closed.
///
/// This defaults to `false` on macOS since that is standard behavior for
/// a macOS application. On Linux, this defaults to `true` since that is
/// generally expected behavior.
///
/// On Linux, if this is `true`, Ghostty can delay quitting fully until a
/// configurable amount of time has passed after the last window is closed.
/// See the documentation of `quit-after-last-window-closed-delay`.
@"quit-after-last-window-closed": bool = builtin.os.tag == .linux,

/// Controls how long Ghostty will stay running after the last open surface has
/// been closed. This only has an effect if `quit-after-last-window-closed` is
/// also set to `true`.
///
/// The minimum value for this configuration is `1s`. Any values lower than
/// this will be clamped to `1s`.
///
/// The duration is specified as a series of numbers followed by time units.
/// Whitespace is allowed between numbers and units. Each number and unit will
/// be added together to form the total duration.
///
/// The allowed time units are as follows:
///
///   * `y` - 365 SI days, or 8760 hours, or 31536000 seconds. No adjustments
///     are made for leap years or leap seconds.
///   * `d` - one SI day, or 86400 seconds.
///   * `h` - one hour, or 3600 seconds.
///   * `m` - one minute, or 60 seconds.
///   * `s` - one second.
///   * `ms` - one millisecond, or 0.001 second.
///   * `us` or `µs` - one microsecond, or 0.000001 second.
///   * `ns` - one nanosecond, or 0.000000001 second.
///
/// Examples:
///   * `1h30m`
///   * `45s`
///
/// Units can be repeated and will be added together. This means that
/// `1h1h` is equivalent to `2h`. This is confusing and should be avoided.
/// A future update may disallow this.
///
/// The maximum value is `584y 49w 23h 34m 33s 709ms 551µs 615ns`. Any
/// value larger than this will be clamped to the maximum value.
///
/// By default `quit-after-last-window-closed-delay` is unset and
/// Ghostty will quit immediately after the last window is closed if
/// `quit-after-last-window-closed` is `true`.
///
/// Only implemented on Linux.
@"quit-after-last-window-closed-delay": ?Duration = null,

/// This controls whether an initial window is created when Ghostty
/// is run. Note that if `quit-after-last-window-closed` is `true` and
/// `quit-after-last-window-closed-delay` is set, setting `initial-window` to
/// `false` will mean that Ghostty will quit after the configured delay if no
/// window is ever created. Only implemented on Linux and macOS.
@"initial-window": bool = true,

/// The position of the "quick" terminal window. To learn more about the
/// quick terminal, see the documentation for the `toggle_quick_terminal`
/// binding action.
///
/// Valid values are:
///
///   * `top` - Terminal appears at the top of the screen.
///   * `bottom` - Terminal appears at the bottom of the screen.
///   * `left` - Terminal appears at the left of the screen.
///   * `right` - Terminal appears at the right of the screen.
///   * `center` - Terminal appears at the center of the screen.
///
/// Changing this configuration requires restarting Ghostty completely.
@"quick-terminal-position": QuickTerminalPosition = .top,

/// The screen where the quick terminal should show up.
///
/// Valid values are:
///
///  * `main` - The screen that the operating system recommends as the main
///    screen. On macOS, this is the screen that is currently receiving
///    keyboard input. This screen is defined by the operating system and
///    not chosen by Ghostty.
///
///  * `mouse` - The screen that the mouse is currently hovered over.
///
///  * `macos-menu-bar` - The screen that contains the macOS menu bar as
///    set in the display settings on macOS. This is a bit confusing because
///    every screen on macOS has a menu bar, but this is the screen that
///    contains the primary menu bar.
///
/// The default value is `main` because this is the recommended screen
/// by the operating system.
@"quick-terminal-screen": QuickTerminalScreen = .main,

/// Duration (in seconds) of the quick terminal enter and exit animation.
/// Set it to 0 to disable animation completely. This can be changed at
/// runtime.
@"quick-terminal-animation-duration": f64 = 0.2,

/// Automatically hide the quick terminal when focus shifts to another window.
/// Set it to false for the quick terminal to remain open even when it loses focus.
@"quick-terminal-autohide": bool = true,

/// Whether to enable shell integration auto-injection or not. Shell integration
/// greatly enhances the terminal experience by enabling a number of features:
///
///   * Working directory reporting so new tabs, splits inherit the
///     previous terminal's working directory.
///
///   * Prompt marking that enables the "jump_to_prompt" keybinding.
///
///   * If you're sitting at a prompt, closing a terminal will not ask
///     for confirmation.
///
///   * Resizing the window with a complex prompt usually paints much
///     better.
///
/// Allowable values are:
///
///   * `none` - Do not do any automatic injection. You can still manually
///     configure your shell to enable the integration.
///
///   * `detect` - Detect the shell based on the filename.
///
///   * `bash`, `elvish`, `fish`, `zsh` - Use this specific shell injection scheme.
///
/// The default value is `detect`.
@"shell-integration": ShellIntegration = .detect,

/// Shell integration features to enable if shell integration itself is enabled.
/// The format of this is a list of features to enable separated by commas. If
/// you prefix a feature with `no-` then it is disabled. If you omit a feature,
/// its default value is used, so you must explicitly disable features you don't
/// want. You can also use `true` or `false` to turn all features on or off.
///
/// Available features:
///
///   * `cursor` - Set the cursor to a blinking bar at the prompt.
///
///   * `sudo` - Set sudo wrapper to preserve terminfo.
///
///   * `title` - Set the window title via shell integration.
///
/// Example: `cursor`, `no-cursor`, `sudo`, `no-sudo`, `title`, `no-title`
@"shell-integration-features": ShellIntegrationFeatures = .{},

/// Sets the reporting format for OSC sequences that request color information.
/// Ghostty currently supports OSC 10 (foreground), OSC 11 (background), and
/// OSC 4 (256 color palette) queries, and by default the reported values
/// are scaled-up RGB values, where each component are 16 bits. This is how
/// most terminals report these values. However, some legacy applications may
/// require 8-bit, unscaled, components. We also support turning off reporting
/// altogether. The components are lowercase hex values.
///
/// Allowable values are:
///
///   * `none` - OSC 4/10/11 queries receive no reply
///
///   * `8-bit` - Color components are return unscaled, i.e. `rr/gg/bb`
///
///   * `16-bit` - Color components are returned scaled, e.g. `rrrr/gggg/bbbb`
///
/// The default value is `16-bit`.
@"osc-color-report-format": OSCColorReportFormat = .@"16-bit",

/// If true, allows the "KAM" mode (ANSI mode 2) to be used within
/// the terminal. KAM disables keyboard input at the request of the
/// application. This is not a common feature and is not recommended
/// to be enabled. This will not be documented further because
/// if you know you need KAM, you know. If you don't know if you
/// need KAM, you don't need it.
@"vt-kam-allowed": bool = false,

/// Custom shaders to run after the default shaders. This is a file path
/// to a GLSL-syntax shader for all platforms.
///
/// Warning: Invalid shaders can cause Ghostty to become unusable such as by
/// causing the window to be completely black. If this happens, you can
/// unset this configuration to disable the shader.
///
/// On Linux, this requires OpenGL 4.2. Ghostty typically only requires
/// OpenGL 3.3, but custom shaders push that requirement up to 4.2.
///
/// The shader API is identical to the Shadertoy API: you specify a `mainImage`
/// function and the available uniforms match Shadertoy. The iChannel0 uniform
/// is a texture containing the rendered terminal screen.
///
/// If the shader fails to compile, the shader will be ignored. Any errors
/// related to shader compilation will not show up as configuration errors
/// and only show up in the log, since shader compilation happens after
/// configuration loading on the dedicated render thread.  For interactive
/// development, use [shadertoy.com](https://shadertoy.com).
///
/// This can be repeated multiple times to load multiple shaders. The shaders
/// will be run in the order they are specified.
///
/// Changing this value at runtime and reloading the configuration will only
/// affect new windows, tabs, and splits.
@"custom-shader": RepeatablePath = .{},

/// If `true` (default), the focused terminal surface will run an animation
/// loop when custom shaders are used. This uses slightly more CPU (generally
/// less than 10%) but allows the shader to animate. This only runs if there
/// are custom shaders and the terminal is focused.
///
/// If this is set to `false`, the terminal and custom shader will only render
/// when the terminal is updated. This is more efficient but the shader will
/// not animate.
///
/// This can also be set to `always`, which will always run the animation
/// loop regardless of whether the terminal is focused or not. The animation
/// loop will still only run when custom shaders are used. Note that this
/// will use more CPU per terminal surface and can become quite expensive
/// depending on the shader and your terminal usage.
///
/// This value can be changed at runtime and will affect all currently
/// open terminals.
@"custom-shader-animation": CustomShaderAnimation = .true,

/// If anything other than false, fullscreen mode on macOS will not use the
/// native fullscreen, but make the window fullscreen without animations and
/// using a new space. It's faster than the native fullscreen mode since it
/// doesn't use animations.
///
/// Important: tabs DO NOT WORK in this mode. Non-native fullscreen removes
/// the titlebar and macOS native tabs require the titlebar. If you use tabs,
/// you should not use this mode.
///
/// If you fullscreen a window with tabs, the currently focused tab will
/// become fullscreen while the others will remain in a separate window in
/// the background. You can switch to that window using normal window-switching
/// keybindings such as command+tilde. When you exit fullscreen, the window
/// will return to the tabbed state it was in before.
///
/// Allowable values are:
///
///   * `visible-menu` - Use non-native macOS fullscreen, keep the menu bar visible
///   * `true` - Use non-native macOS fullscreen, hide the menu bar
///   * `false` - Use native macOS fullscreen
///
/// Changing this option at runtime works, but will only apply to the next
/// time the window is made fullscreen. If a window is already fullscreen,
/// it will retain the previous setting until fullscreen is exited.
@"macos-non-native-fullscreen": NonNativeFullscreen = .false,

/// The style of the macOS titlebar. Available values are: "native",
/// "transparent", "tabs", and "hidden".
///
/// The "native" style uses the native macOS titlebar with zero customization.
/// The titlebar will match your window theme (see `window-theme`).
///
/// The "transparent" style is the same as "native" but the titlebar will
/// be transparent and allow your window background color to come through.
/// This makes a more seamless window appearance but looks a little less
/// typical for a macOS application and may not work well with all themes.
///
/// The "transparent" style will also update in real-time to dynamic
/// changes to the window background color, i.e. via OSC 11. To make this
/// more aesthetically pleasing, this only happens if the terminal is
/// a window, tab, or split that borders the top of the window. This
/// avoids a disjointed appearance where the titlebar color changes
/// but all the topmost terminals don't match.
///
/// The "tabs" style is a completely custom titlebar that integrates the
/// tab bar into the titlebar. This titlebar always matches the background
/// color of the terminal. There are some limitations to this style:
/// On macOS 13 and below, saved window state will not restore tabs correctly.
/// macOS 14 does not have this issue and any other macOS version has not
/// been tested.
///
/// The "hidden" style hides the titlebar. Unlike `window-decoration = false`,
/// however, it does not remove the frame from the window or cause it to have
/// squared corners. Changing to or from this option at run-time may affect
/// existing windows in buggy ways. The top titlebar area of the window will
/// continue to drag the window around and you will not be able to use
/// the mouse for terminal events in this space.
///
/// The default value is "transparent". This is an opinionated choice
/// but its one I think is the most aesthetically pleasing and works in
/// most cases.
///
/// Changing this option at runtime only applies to new windows.
@"macos-titlebar-style": MacTitlebarStyle = .transparent,

/// Whether the proxy icon in the macOS titlebar is visible. The proxy icon
/// is the icon that represents the folder of the current working directory.
/// You can see this very clearly in the macOS built-in Terminal.app
/// titlebar.
///
/// The proxy icon is only visible with the native macOS titlebar style.
///
/// Valid values are:
///
///   * `visible` - Show the proxy icon.
///   * `hidden` - Hide the proxy icon.
///
/// The default value is `visible`.
///
/// This setting can be changed at runtime and will affect all currently
/// open windows but only after their working directory changes again.
/// Therefore, to make this work after changing the setting, you must
/// usually `cd` to a different directory, open a different file in an
/// editor, etc.
@"macos-titlebar-proxy-icon": MacTitlebarProxyIcon = .visible,

/// macOS doesn't have a distinct "alt" key and instead has the "option"
/// key which behaves slightly differently. On macOS by default, the
/// option key plus a character will sometimes produces a Unicode character.
/// For example, on US standard layouts option-b produces "∫". This may be
/// undesirable if you want to use "option" as an "alt" key for keybindings
/// in terminal programs or shells.
///
/// This configuration lets you change the behavior so that option is treated
/// as alt.
///
/// The default behavior (unset) will depend on your active keyboard
/// layout. If your keyboard layout is one of the keyboard layouts listed
/// below, then the default value is "true". Otherwise, the default
/// value is "false". Keyboard layouts with a default value of "true" are:
///
///   - U.S. Standard
///   - U.S. International
///
/// Note that if an *Option*-sequence doesn't produce a printable character, it
/// will be treated as *Alt* regardless of this setting. (i.e. `alt+ctrl+a`).
///
/// Explicit values that can be set:
///
/// If `true`, the *Option* key will be treated as *Alt*. This makes terminal
/// sequences expecting *Alt* to work properly, but will break Unicode input
/// sequences on macOS if you use them via the *Alt* key.
///
/// You may set this to `false` to restore the macOS *Alt* key unicode
/// sequences but this will break terminal sequences expecting *Alt* to work.
///
/// The values `left` or `right` enable this for the left or right *Option*
/// key, respectively.
///
/// This does not work with GLFW builds.
@"macos-option-as-alt": ?OptionAsAlt = null,

/// Whether to enable the macOS window shadow. The default value is true.
/// With some window managers and window transparency settings, you may
/// find false more visually appealing.
@"macos-window-shadow": bool = true,

/// If true, Ghostty on macOS will automatically enable the "Secure Input"
/// feature when it detects that a password prompt is being displayed.
///
/// "Secure Input" is a macOS security feature that prevents applications from
/// reading keyboard events. This can always be enabled manually using the
/// `Ghostty > Secure Keyboard Entry` menu item.
///
/// Note that automatic password prompt detection is based on heuristics
/// and may not always work as expected. Specifically, it does not work
/// over SSH connections, but there may be other cases where it also
/// doesn't work.
///
/// A reason to disable this feature is if you find that it is interfering
/// with legitimate accessibility software (or software that uses the
/// accessibility APIs), since secure input prevents any application from
/// reading keyboard events.
@"macos-auto-secure-input": bool = true,

/// If true, Ghostty will show a graphical indication when secure input is
/// enabled. This indication is generally recommended to know when secure input
/// is enabled.
///
/// Normally, secure input is only active when a password prompt is displayed
/// or it is manually (and typically temporarily) enabled. However, if you
/// always have secure input enabled, the indication can be distracting and
/// you may want to disable it.
@"macos-secure-input-indication": bool = true,

/// Customize the macOS app icon.
///
/// This only affects the icon that appears in the dock, application
/// switcher, etc. This does not affect the icon in Finder because
/// that is controlled by a hardcoded value in the signed application
/// bundle and can't be changed at runtime. For more details on what
/// exactly is affected, see the `NSApplication.icon` Apple documentation;
/// that is the API that is being used to set the icon.
///
/// Valid values:
///
///  * `official` - Use the official Ghostty icon.
///  * `custom-style` - Use the official Ghostty icon but with custom
///    styles applied to various layers. The custom styles must be
///    specified using the additional `macos-icon`-prefixed configurations.
///    The `macos-icon-ghost-color` and `macos-icon-screen-color`
///    configurations are required for this style.
///
/// WARNING: The `custom-style` option is _experimental_. We may change
/// the format of the custom styles in the future. We're still finalizing
/// the exact layers and customization options that will be available.
///
/// Other caveats:
///
///   * The icon in the update dialog will always be the official icon.
///     This is because the update dialog is managed through a
///     separate framework and cannot be customized without significant
///     effort.
///
@"macos-icon": MacAppIcon = .official,

/// The material to use for the frame of the macOS app icon.
///
/// Valid values:
///
///  * `aluminum` - A brushed aluminum frame. This is the default.
///  * `beige` - A classic 90's computer beige frame.
///  * `plastic` - A glossy, dark plastic frame.
///  * `chrome` - A shiny chrome frame.
///
/// This only has an effect when `macos-icon` is set to `custom-style`.
@"macos-icon-frame": MacAppIconFrame = .aluminum,

/// The color of the ghost in the macOS app icon.
///
/// The format of the color is the same as the `background` configuration;
/// see that for more information.
///
/// Note: This configuration is required when `macos-icon` is set to
/// `custom-style`.
///
/// This only has an effect when `macos-icon` is set to `custom-style`.
@"macos-icon-ghost-color": ?Color = null,

/// The color of the screen in the macOS app icon.
///
/// The screen is a gradient so you can specify multiple colors that
/// make up the gradient. Colors should be separated by commas. The
/// format of the color is the same as the `background` configuration;
/// see that for more information.
///
/// Note: This configuration is required when `macos-icon` is set to
/// `custom-style`.
///
/// This only has an effect when `macos-icon` is set to `custom-style`.
@"macos-icon-screen-color": ?ColorList = null,

/// Put every surface (tab, split, window) into a dedicated Linux cgroup.
///
/// This makes it so that resource management can be done on a per-surface
/// granularity. For example, if a shell program is using too much memory,
/// only that shell will be killed by the oom monitor instead of the entire
/// Ghostty process. Similarly, if a shell program is using too much CPU,
/// only that surface will be CPU-throttled.
///
/// This will cause startup times to be slower (a hundred milliseconds or so),
/// so the default value is "single-instance." In single-instance mode, only
/// one instance of Ghostty is running (see gtk-single-instance) so the startup
/// time is a one-time cost. Additionally, single instance Ghostty is much
/// more likely to have many windows, tabs, etc. so cgroup isolation is a
/// big benefit.
///
/// This feature requires systemd. If systemd is unavailable, cgroup
/// initialization will fail. By default, this will not prevent Ghostty
/// from working (see linux-cgroup-hard-fail).
///
/// Valid values are:
///
///   * `never` - Never use cgroups.
///   * `always` - Always use cgroups.
///   * `single-instance` - Enable cgroups only for Ghostty instances launched
///     as single-instance applications (see gtk-single-instance).
///
@"linux-cgroup": LinuxCgroup = .@"single-instance",

/// Memory limit for any individual terminal process (tab, split, window,
/// etc.) in bytes. If this is unset then no memory limit will be set.
///
/// Note that this sets the "memory.high" configuration for the memory
/// controller, which is a soft limit. You should configure something like
/// systemd-oom to handle killing processes that have too much memory
/// pressure.
@"linux-cgroup-memory-limit": ?u64 = null,

/// Number of processes limit for any individual terminal process (tab, split,
/// window, etc.). If this is unset then no limit will be set.
///
/// Note that this sets the "pids.max" configuration for the process number
/// controller, which is a hard limit.
@"linux-cgroup-processes-limit": ?u64 = null,

/// If this is false, then any cgroup initialization (for linux-cgroup)
/// will be allowed to fail and the failure is ignored. This is useful if
/// you view cgroup isolation as a "nice to have" and not a critical resource
/// management feature, because Ghostty startup will not fail if cgroup APIs
/// fail.
///
/// If this is true, then any cgroup initialization failure will cause
/// Ghostty to exit or new surfaces to not be created.
///
/// Note: This currently only affects cgroup initialization. Subprocesses
/// must always be able to move themselves into an isolated cgroup.
@"linux-cgroup-hard-fail": bool = false,

/// If `true`, the Ghostty GTK application will run in single-instance mode:
/// each new `ghostty` process launched will result in a new window if there is
/// already a running process.
///
/// If `false`, each new ghostty process will launch a separate application.
///
/// The default value is `detect` which will default to `true` if Ghostty
/// detects that it was launched from the `.desktop` file such as an app
/// launcher (like Gnome Shell)  or by D-Bus activation. If Ghostty is launched
/// from the command line, it will default to `false`.
///
/// Note that debug builds of Ghostty have a separate single-instance ID
/// so you can test single instance without conflicting with release builds.
@"gtk-single-instance": GtkSingleInstance = .desktop,

/// When enabled, the full GTK titlebar is displayed instead of your window
/// manager's simple titlebar. The behavior of this option will vary with your
/// window manager.
///
/// This option does nothing when `window-decoration` is false or when running
/// under macOS.
///
/// Changing this value at runtime and reloading the configuration will only
/// affect new windows.
@"gtk-titlebar": bool = true,

/// Determines the side of the screen that the GTK tab bar will stick to.
/// Top, bottom, left, right, and hidden are supported. The default is top.
///
/// If this option has value `left` or `right` when using Adwaita, it falls
/// back to `top`. `hidden`, meaning that tabs don't exist, is not supported
/// without using Adwaita, falling back to `top`.
///
/// When `hidden` is set and Adwaita is enabled, a tab button displaying the
/// number of tabs will appear in the title bar. It has the ability to open a
/// tab overview for displaying tabs. Alternatively, you can use the
/// `toggle_tab_overview` action in a keybind if your window doesn't have a
/// title bar, or you can switch tabs with keybinds.
@"gtk-tabs-location": GtkTabsLocation = .top,

/// Determines the appearance of the top and bottom bars when using the
/// Adwaita tab bar. This requires `gtk-adwaita` to be enabled (it is
/// by default).
///
/// Valid values are:
///
///  * `flat` - Top and bottom bars are flat with the terminal window.
///  * `raised` - Top and bottom bars cast a shadow on the terminal area.
///  * `raised-border` - Similar to `raised` but the shadow is replaced with a
///    more subtle border.
///
/// Changing this value at runtime will only affect new windows.
@"adw-toolbar-style": AdwToolbarStyle = .raised,

/// If `true` (default), then the Ghostty GTK tabs will be "wide." Wide tabs
/// are the new typical Gnome style where tabs fill their available space.
/// If you set this to `false` then tabs will only take up space they need,
/// which is the old style.
@"gtk-wide-tabs": bool = true,

/// If `true` (default), Ghostty will enable Adwaita theme support. This
/// will make `window-theme` work properly and will also allow Ghostty to
/// properly respond to system theme changes, light/dark mode changing, etc.
/// This requires a GTK4 desktop with a GTK4 theme.
///
/// If you are running GTK3 or have a GTK3 theme, you may have to set this
/// to false to get your theme picked up properly. Having this set to true
/// with GTK3 should not cause any problems, but it may not work exactly as
/// expected.
///
/// This configuration only has an effect if Ghostty was built with
/// Adwaita support.
@"gtk-adwaita": bool = true,

/// If `true` (default), applications running in the terminal can show desktop
/// notifications using certain escape sequences such as OSC 9 or OSC 777.
@"desktop-notifications": bool = true,

/// If `true`, the bold text will use the bright color palette.
@"bold-is-bright": bool = false,

/// This will be used to set the `TERM` environment variable.
/// HACK: We set this with an `xterm` prefix because vim uses that to enable key
/// protocols (specifically this will enable `modifyOtherKeys`), among other
/// features. An option exists in vim to modify this: `:set
/// keyprotocol=ghostty:kitty`, however a bug in the implementation prevents it
/// from working properly. https://github.com/vim/vim/pull/13211 fixes this.
term: []const u8 = "xterm-ghostty",

/// String to send when we receive `ENQ` (`0x05`) from the command that we are
/// running. Defaults to an empty string if not set.
@"enquiry-response": []const u8 = "",

/// Control the auto-update functionality of Ghostty. This is only supported
/// on macOS currently, since Linux builds are distributed via package
/// managers that are not centrally controlled by Ghostty.
///
/// Checking or downloading an update does not send any information to
/// the project beyond standard network information mandated by the
/// underlying protocols. To put it another way: Ghostty doesn't explicitly
/// add any tracking to the update process. The update process works by
/// downloading information about the latest version and comparing it
/// client-side to the current version.
///
/// Valid values are:
///
///  * `off` - Disable auto-updates.
///  * `check` - Check for updates and notify the user if an update is
///    available, but do not automatically download or install the update.
///  * `download` - Check for updates, automatically download the update,
///    notify the user, but do not automatically install the update.
///
/// The default value is `check`.
///
/// Changing this value at runtime works after a small delay.
@"auto-update": AutoUpdate = .check,

/// The release channel to use for auto-updates.
///
/// The default value of this matches the release channel of the currently
/// running Ghostty version. If you download a pre-release version of Ghostty
/// then this will be set to `tip` and you will receive pre-release updates.
/// If you download a stable version of Ghostty then this will be set to
/// `stable` and you will receive stable updates.
///
/// Valid values are:
///
///  * `stable` - Stable, tagged releases such as "1.0.0".
///  * `tip` - Pre-release versions generated from each commit to the
///    main branch. This is the version that was in use during private
///    beta testing by thousands of people. It is generally stable but
///    will likely have more bugs than the stable channel.
///
/// Changing this configuration requires a full restart of
/// Ghostty to take effect.
///
/// This only works on macOS since only macOS has an auto-update feature.
@"auto-update-channel": ?build_config.ReleaseChannel = null,

/// This is set by the CLI parser for deinit.
_arena: ?ArenaAllocator = null,

/// List of diagnostics that were generated during the loading of
/// the configuration.
_diagnostics: cli.DiagnosticList = .{},

/// The conditional truths for the configuration. This is used to
/// determine if a conditional configuration matches or not.
_conditional_state: conditional.State = .{},

/// The conditional keys that are used at any point during the configuration
/// loading. This is used to speed up the conditional evaluation process.
_conditional_set: std.EnumSet(conditional.Key) = .{},

/// The steps we can use to reload the configuration after it has been loaded
/// without reopening the files. This is used in very specific cases such
/// as loadTheme which has more details on why.
_replay_steps: std.ArrayListUnmanaged(Replay.Step) = .{},

/// Set to true if Ghostty was executed as xdg-terminal-exec on Linux.
@"_xdg-terminal-exec": bool = false,

pub fn deinit(self: *Config) void {
    if (self._arena) |arena| arena.deinit();
    self.* = undefined;
}

/// Load the configuration according to the default rules:
///
///   1. Defaults
///   2. XDG config dir
///   3. "Application Support" directory (macOS only)
///   4. CLI flags
///   5. Recursively defined configuration files
///
pub fn load(alloc_gpa: Allocator) !Config {
    var result = try default(alloc_gpa);
    errdefer result.deinit();

    // If we have a configuration file in our home directory, parse that first.
    try result.loadDefaultFiles(alloc_gpa);

    // Parse the config from the CLI args.
    try result.loadCliArgs(alloc_gpa);

    // Parse the config files that were added from our file and CLI args.
    try result.loadRecursiveFiles(alloc_gpa);
    try result.finalize();

    return result;
}

pub fn default(alloc_gpa: Allocator) Allocator.Error!Config {
    // Build up our basic config
    var result: Config = .{
        ._arena = ArenaAllocator.init(alloc_gpa),
    };
    errdefer result.deinit();
    const alloc = result._arena.?.allocator();

    // Add our default keybindings

    // keybinds for opening and reloading config
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .comma }, .mods = inputpkg.ctrlOrSuper(.{ .shift = true }) },
        .{ .reload_config = {} },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .comma }, .mods = inputpkg.ctrlOrSuper(.{}) },
        .{ .open_config = {} },
    );

    {
        // On macOS we default to super but Linux ctrl+shift since
        // ctrl+c is to kill the process.
        const mods: inputpkg.Mods = if (builtin.target.isDarwin())
            .{ .super = true }
        else
            .{ .ctrl = true, .shift = true };

        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .c }, .mods = mods },
            .{ .copy_to_clipboard = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .v }, .mods = mods },
            .{ .paste_from_clipboard = {} },
        );
    }

    // Increase font size mapping for keyboards with dedicated plus keys (like german)
    // Note: this order matters below because the C API will only return
    // the last keybinding for a given action. The macOS app uses this to
    // set the expected keybind for the menu.
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .plus }, .mods = inputpkg.ctrlOrSuper(.{}) },
        .{ .increase_font_size = 1 },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .equal }, .mods = inputpkg.ctrlOrSuper(.{}) },
        .{ .increase_font_size = 1 },
    );

    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .minus }, .mods = inputpkg.ctrlOrSuper(.{}) },
        .{ .decrease_font_size = 1 },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .zero }, .mods = inputpkg.ctrlOrSuper(.{}) },
        .{ .reset_font_size = {} },
    );

    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .j }, .mods = inputpkg.ctrlOrSuper(.{ .shift = true }) },
        .{ .write_scrollback_file = .paste },
    );

    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .j }, .mods = inputpkg.ctrlOrSuper(.{ .shift = true, .alt = true }) },
        .{ .write_scrollback_file = .open },
    );

    // Expand Selection
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .left }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .left },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .right }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .right },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .up }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .up },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .down }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .down },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .page_up }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .page_up },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .page_down }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .page_down },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .home }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .home },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .end }, .mods = .{ .shift = true } },
        .{ .adjust_selection = .end },
    );

    // Tabs common to all platforms
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .tab }, .mods = .{ .ctrl = true, .shift = true } },
        .{ .previous_tab = {} },
    );
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .tab }, .mods = .{ .ctrl = true } },
        .{ .next_tab = {} },
    );

    // Windowing
    if (comptime !builtin.target.isDarwin()) {
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .n }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .new_window = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .w }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .close_surface = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .q }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .quit = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .f4 }, .mods = .{ .alt = true } },
            .{ .close_window = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .t }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .new_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .previous_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .next_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_up }, .mods = .{ .ctrl = true } },
            .{ .previous_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_down }, .mods = .{ .ctrl = true } },
            .{ .next_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .o }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .new_split = .right },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .e }, .mods = .{ .ctrl = true, .shift = true } },
            .{ .new_split = .down },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left_bracket }, .mods = .{ .ctrl = true, .super = true } },
            .{ .goto_split = .previous },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right_bracket }, .mods = .{ .ctrl = true, .super = true } },
            .{ .goto_split = .next },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .up }, .mods = .{ .ctrl = true, .alt = true } },
            .{ .goto_split = .top },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .down }, .mods = .{ .ctrl = true, .alt = true } },
            .{ .goto_split = .bottom },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .ctrl = true, .alt = true } },
            .{ .goto_split = .left },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .ctrl = true, .alt = true } },
            .{ .goto_split = .right },
        );

        // Resizing splits
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .up }, .mods = .{ .super = true, .ctrl = true, .shift = true } },
            .{ .resize_split = .{ .up, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .down }, .mods = .{ .super = true, .ctrl = true, .shift = true } },
            .{ .resize_split = .{ .down, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .super = true, .ctrl = true, .shift = true } },
            .{ .resize_split = .{ .left, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .super = true, .ctrl = true, .shift = true } },
            .{ .resize_split = .{ .right, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .equal }, .mods = .{ .super = true, .ctrl = true, .shift = true } },
            .{ .equalize_splits = {} },
        );

        // Viewport scrolling
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .home }, .mods = .{ .shift = true } },
            .{ .scroll_to_top = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .end }, .mods = .{ .shift = true } },
            .{ .scroll_to_bottom = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_up }, .mods = .{ .shift = true } },
            .{ .scroll_page_up = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_down }, .mods = .{ .shift = true } },
            .{ .scroll_page_down = {} },
        );

        // Semantic prompts
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_up }, .mods = .{ .shift = true, .ctrl = true } },
            .{ .jump_to_prompt = -1 },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_down }, .mods = .{ .shift = true, .ctrl = true } },
            .{ .jump_to_prompt = 1 },
        );

        // Inspector, matching Chromium
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .i }, .mods = .{ .shift = true, .ctrl = true } },
            .{ .inspector = .toggle },
        );

        // Terminal
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .a }, .mods = .{ .shift = true, .ctrl = true } },
            .{ .select_all = {} },
        );

        // Selection clipboard paste
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .insert }, .mods = .{ .shift = true } },
            .{ .paste_from_selection = {} },
        );
    }
    {
        // On macOS we default to super but everywhere else
        // is alt.
        const mods: inputpkg.Mods = if (builtin.target.isDarwin())
            .{ .super = true }
        else
            .{ .alt = true };

        // Cmd+N for goto tab N
        const start = @intFromEnum(inputpkg.Key.one);
        const end = @intFromEnum(inputpkg.Key.eight);
        var i: usize = start;
        while (i <= end) : (i += 1) {
            try result.keybind.set.put(
                alloc,
                .{
                    // On macOS, we use the physical key for tab changing so
                    // that this works across all keyboard layouts. This may
                    // want to be true on other platforms as well but this
                    // is definitely true on macOS so we just do it here for
                    // now (#817)
                    .key = if (comptime builtin.target.isDarwin())
                        .{ .physical = @enumFromInt(i) }
                    else
                        .{ .translated = @enumFromInt(i) },

                    .mods = mods,
                },
                .{ .goto_tab = (i - start) + 1 },
            );
        }
        try result.keybind.set.put(
            alloc,
            .{
                .key = if (comptime builtin.target.isDarwin())
                    .{ .physical = .nine }
                else
                    .{ .translated = .nine },
                .mods = mods,
            },
            .{ .last_tab = {} },
        );
    }

    // Toggle fullscreen
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .enter }, .mods = inputpkg.ctrlOrSuper(.{}) },
        .{ .toggle_fullscreen = {} },
    );

    // Toggle zoom a split
    try result.keybind.set.put(
        alloc,
        .{ .key = .{ .translated = .enter }, .mods = inputpkg.ctrlOrSuper(.{ .shift = true }) },
        .{ .toggle_split_zoom = {} },
    );

    // Mac-specific keyboard bindings.
    if (comptime builtin.target.isDarwin()) {
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .q }, .mods = .{ .super = true } },
            .{ .quit = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .k }, .mods = .{ .super = true } },
            .{ .clear_screen = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .a }, .mods = .{ .super = true } },
            .{ .select_all = {} },
        );

        // Viewport scrolling
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .home }, .mods = .{ .super = true } },
            .{ .scroll_to_top = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .end }, .mods = .{ .super = true } },
            .{ .scroll_to_bottom = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_up }, .mods = .{ .super = true } },
            .{ .scroll_page_up = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .page_down }, .mods = .{ .super = true } },
            .{ .scroll_page_down = {} },
        );

        // Semantic prompts
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .up }, .mods = .{ .super = true, .shift = true } },
            .{ .jump_to_prompt = -1 },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .down }, .mods = .{ .super = true, .shift = true } },
            .{ .jump_to_prompt = 1 },
        );

        // Mac windowing
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .n }, .mods = .{ .super = true } },
            .{ .new_window = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .w }, .mods = .{ .super = true } },
            .{ .close_surface = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .w }, .mods = .{ .super = true, .shift = true } },
            .{ .close_window = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .w }, .mods = .{ .super = true, .shift = true, .alt = true } },
            .{ .close_all_windows = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .t }, .mods = .{ .super = true } },
            .{ .new_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left_bracket }, .mods = .{ .super = true, .shift = true } },
            .{ .previous_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right_bracket }, .mods = .{ .super = true, .shift = true } },
            .{ .next_tab = {} },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .d }, .mods = .{ .super = true } },
            .{ .new_split = .right },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .d }, .mods = .{ .super = true, .shift = true } },
            .{ .new_split = .down },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left_bracket }, .mods = .{ .super = true } },
            .{ .goto_split = .previous },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right_bracket }, .mods = .{ .super = true } },
            .{ .goto_split = .next },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .up }, .mods = .{ .super = true, .alt = true } },
            .{ .goto_split = .top },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .down }, .mods = .{ .super = true, .alt = true } },
            .{ .goto_split = .bottom },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .super = true, .alt = true } },
            .{ .goto_split = .left },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .super = true, .alt = true } },
            .{ .goto_split = .right },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .up }, .mods = .{ .super = true, .ctrl = true } },
            .{ .resize_split = .{ .up, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .down }, .mods = .{ .super = true, .ctrl = true } },
            .{ .resize_split = .{ .down, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .super = true, .ctrl = true } },
            .{ .resize_split = .{ .left, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .super = true, .ctrl = true } },
            .{ .resize_split = .{ .right, 10 } },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .equal }, .mods = .{ .super = true, .ctrl = true } },
            .{ .equalize_splits = {} },
        );

        // Jump to prompt, matches Terminal.app
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .up }, .mods = .{ .super = true } },
            .{ .jump_to_prompt = -1 },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .down }, .mods = .{ .super = true } },
            .{ .jump_to_prompt = 1 },
        );

        // Inspector, matching Chromium
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .i }, .mods = .{ .alt = true, .super = true } },
            .{ .inspector = .toggle },
        );

        // Alternate keybind, common to Mac programs
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .f }, .mods = .{ .super = true, .ctrl = true } },
            .{ .toggle_fullscreen = {} },
        );

        // "Natural text editing" keybinds. This forces these keys to go back
        // to legacy encoding (not fixterms). It seems macOS users more than
        // others are used to these keys so we set them as defaults. If
        // people want to get back to the fixterm encoding they can set
        // the keybinds to `unbind`.
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .super = true } },
            .{ .text = "\\x05" },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .super = true } },
            .{ .text = "\\x01" },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .left }, .mods = .{ .alt = true } },
            .{ .esc = "b" },
        );
        try result.keybind.set.put(
            alloc,
            .{ .key = .{ .translated = .right }, .mods = .{ .alt = true } },
            .{ .esc = "f" },
        );
    }

    // Add our default link for URL detection
    try result.link.links.append(alloc, .{
        .regex = url.regex,
        .action = .{ .open = {} },
        .highlight = .{ .hover_mods = inputpkg.ctrlOrSuper(.{}) },
    });

    return result;
}

/// Load configuration from an iterator that yields values that look like
/// command-line arguments, i.e. `--key=value`.
pub fn loadIter(
    self: *Config,
    alloc: Allocator,
    iter: anytype,
) !void {
    try cli.args.parse(Config, alloc, self, iter);
}

/// Load configuration from the target config file at `path`.
///
/// `path` must be resolved and absolute.
pub fn loadFile(self: *Config, alloc: Allocator, path: []const u8) !void {
    assert(std.fs.path.isAbsolute(path));

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const stat = try file.stat();
    switch (stat.kind) {
        .file => {},
        else => |kind| {
            log.warn("config-file {s}: not reading because file type is {s}", .{
                path,
                @tagName(kind),
            });
            return;
        },
    }

    std.log.info("reading configuration file path={s}", .{path});

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();
    const Iter = cli.args.LineIterator(@TypeOf(reader));
    var iter: Iter = .{ .r = reader, .filepath = path };
    try self.loadIter(alloc, &iter);
    try self.expandPaths(std.fs.path.dirname(path).?);
}

/// Load optional configuration file from `path`. All errors are ignored.
pub fn loadOptionalFile(self: *Config, alloc: Allocator, path: []const u8) void {
    self.loadFile(alloc, path) catch |err| switch (err) {
        error.FileNotFound => std.log.info(
            "optional config file not found, not loading path={s}",
            .{path},
        ),
        else => std.log.warn(
            "error reading optional config file, not loading err={} path={s}",
            .{ err, path },
        ),
    };
}

/// Load configurations from the default configuration files. The default
/// configuration file is at `$XDG_CONFIG_HOME/ghostty/config`.
///
/// On macOS, `$HOME/Library/Application Support/$CFBundleIdentifier/config`
/// is also loaded.
pub fn loadDefaultFiles(self: *Config, alloc: Allocator) !void {
    const xdg_path = try internal_os.xdg.config(alloc, .{ .subdir = "ghostty/config" });
    defer alloc.free(xdg_path);
    self.loadOptionalFile(alloc, xdg_path);

    if (comptime builtin.os.tag == .macos) {
        const app_support_path = try internal_os.macos.appSupportDir(alloc, "config");
        defer alloc.free(app_support_path);
        self.loadOptionalFile(alloc, app_support_path);
    }
}

/// Load and parse the CLI args.
pub fn loadCliArgs(self: *Config, alloc_gpa: Allocator) !void {
    switch (builtin.os.tag) {
        .windows => {},

        // Fast-path if we are Linux and have no args.
        .linux => if (std.os.argv.len <= 1) return,

        // Everything else we have to at least try because it may
        // not use std.os.argv.
        else => {},
    }

    // On Linux, we have a special case where if the executing
    // program is "xdg-terminal-exec" then we treat all CLI
    // args as if they are a command to execute.
    //
    // In this mode, we also behave slightly differently:
    //
    //   - The initial window title is set to the full command. This
    //     can be used with window managers to modify positioning,
    //     styling, etc. based on the command.
    //
    // See: https://github.com/Vladimir-csp/xdg-terminal-exec
    if (comptime builtin.os.tag == .linux) {
        if (internal_os.xdg.parseTerminalExec(std.os.argv)) |args| {
            const arena_alloc = self._arena.?.allocator();

            // First, we add an artificial "-e" so that if we
            // replay the inputs to rebuild the config (i.e. if
            // a theme is set) then we will get the same behavior.
            try self._replay_steps.append(arena_alloc, .@"-e");

            // Next, take all remaining args and use that to build up
            // a command to execute.
            var command = std.ArrayList(u8).init(arena_alloc);
            errdefer command.deinit();
            for (args) |arg_raw| {
                const arg = std.mem.sliceTo(arg_raw, 0);
                try self._replay_steps.append(
                    arena_alloc,
                    .{ .arg = try arena_alloc.dupe(u8, arg) },
                );

                try command.appendSlice(arg);
                try command.append(' ');
            }

            self.@"_xdg-terminal-exec" = true;
            self.@"initial-command" = command.items[0 .. command.items.len - 1];
            return;
        }
    }

    // We set config-default-files to true here because this
    // should always be reset so we can detect if it is set
    // in the CLI since it is documented as having no affect
    // from files.
    self.@"config-default-files" = true;

    // Keep track of the replay steps up to this point so we
    // can replay if we are disgarding the default files.
    const replay_len_start = self._replay_steps.items.len;

    // Keep track of font families because if they are set from the CLI
    // then we clear the previously set values. This avoids a UX oddity
    // where on the CLI you have to specify `font-family=""` to clear the
    // font families before setting a new one.
    const fields = &[_][]const u8{
        "font-family",
        "font-family-bold",
        "font-family-italic",
        "font-family-bold-italic",
    };
    var counter: [fields.len]usize = undefined;
    inline for (fields, 0..) |field, i| {
        counter[i] = @field(self, field).list.items.len;
    }

    // Initialize our CLI iterator.
    var iter = try cli.args.argsIterator(alloc_gpa);
    defer iter.deinit();
    try self.loadIter(alloc_gpa, &iter);

    // If we are not loading the default files, then we need to
    // replay the steps up to this point so that we can rebuild
    // the config without it.
    if (!self.@"config-default-files") reload: {
        const replay_len_end = self._replay_steps.items.len;
        if (replay_len_end == replay_len_start) break :reload;
        log.info("config-default-files unset, discarding configuration from default files", .{});

        var new_config = try self.cloneEmpty(alloc_gpa);
        errdefer new_config.deinit();
        var it = Replay.iterator(
            self._replay_steps.items[replay_len_start..replay_len_end],
            &new_config,
        );
        try new_config.loadIter(alloc_gpa, &it);
        self.deinit();
        self.* = new_config;
    } else {
        // If any of our font family settings were changed, then we
        // replace the entire list with the new list.
        inline for (fields, 0..) |field, i| {
            const v = &@field(self, field);
            const len = v.list.items.len - counter[i];
            if (len > 0) {
                // Note: we don't have to worry about freeing the memory
                // that we overwrite or cut off here because its all in
                // an arena.
                v.list.replaceRangeAssumeCapacity(
                    0,
                    len,
                    v.list.items[counter[i]..],
                );
                v.list.items.len = len;
            }
        }
    }

    // Config files loaded from the CLI args are relative to pwd
    if (self.@"config-file".value.items.len > 0) {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        try self.expandPaths(try std.fs.cwd().realpath(".", &buf));
    }
}

/// Load and parse the config files that were added in the "config-file" key.
pub fn loadRecursiveFiles(self: *Config, alloc_gpa: Allocator) !void {
    if (self.@"config-file".value.items.len == 0) return;
    const arena_alloc = self._arena.?.allocator();

    // Keeps track of loaded files to prevent cycles.
    var loaded = std.StringHashMap(void).init(alloc_gpa);
    defer loaded.deinit();

    // We need to insert all of our loaded config-file values
    // PRIOR to the "-e" in our replay steps, since everything
    // after "-e" becomes an "initial-command". To do this, we
    // dupe the values if we find it.
    var replay_suffix = std.ArrayList(Replay.Step).init(alloc_gpa);
    defer replay_suffix.deinit();
    for (self._replay_steps.items, 0..) |step, i| if (step == .@"-e") {
        // We don't need to clone the steps because they should
        // all be allocated in our arena and we're keeping our
        // arena.
        try replay_suffix.appendSlice(self._replay_steps.items[i..]);

        // Remove our old values. Again, don't need to free any
        // memory here because its all part of our arena.
        self._replay_steps.shrinkRetainingCapacity(i);
        break;
    };

    // We must use a while below and not a for(items) because we
    // may add items to the list while iterating for recursive
    // config-file entries.
    var i: usize = 0;
    while (i < self.@"config-file".value.items.len) : (i += 1) {
        const path, const optional = switch (self.@"config-file".value.items[i]) {
            .optional => |path| .{ path, true },
            .required => |path| .{ path, false },
        };

        // Error paths
        if (path.len == 0) continue;

        // All paths should already be absolute at this point because
        // they're fixed up after each load.
        assert(std.fs.path.isAbsolute(path));

        // We must only load a unique file once
        if (try loaded.fetchPut(path, {}) != null) {
            try self._diagnostics.append(arena_alloc, .{
                .message = try std.fmt.allocPrintZ(
                    arena_alloc,
                    "config-file {s}: cycle detected",
                    .{path},
                ),
            });
            continue;
        }

        var file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err != error.FileNotFound or !optional) {
                try self._diagnostics.append(arena_alloc, .{
                    .message = try std.fmt.allocPrintZ(
                        arena_alloc,
                        "error opening config-file {s}: {}",
                        .{ path, err },
                    ),
                });
            }
            continue;
        };
        defer file.close();

        const stat = try file.stat();
        switch (stat.kind) {
            .file => {},
            else => |kind| {
                try self._diagnostics.append(arena_alloc, .{
                    .message = try std.fmt.allocPrintZ(
                        arena_alloc,
                        "config-file {s}: not reading because file type is {s}",
                        .{ path, @tagName(kind) },
                    ),
                });
                continue;
            },
        }

        log.info("loading config-file path={s}", .{path});
        var buf_reader = std.io.bufferedReader(file.reader());
        const reader = buf_reader.reader();
        const Iter = cli.args.LineIterator(@TypeOf(reader));
        var iter: Iter = .{ .r = reader, .filepath = path };
        try self.loadIter(alloc_gpa, &iter);
        try self.expandPaths(std.fs.path.dirname(path).?);
    }

    // If we have a suffix, add that back.
    if (replay_suffix.items.len > 0) {
        try self._replay_steps.appendSlice(
            arena_alloc,
            replay_suffix.items,
        );
    }
}

/// Change the state of conditionals and reload the configuration
/// based on the new state. This returns a new configuration based
/// on the new state. The caller must free the old configuration if they
/// wish.
///
/// This returns null if the conditional state would result in no changes
/// to the configuration. In this case, the caller can continue to use
/// the existing configuration or clone if they want a copy.
///
/// This doesn't re-read any files, it just re-applies the same
/// configuration with the new conditional state. Importantly, this means
/// that if you change the conditional state and the user in the interim
/// deleted a file that was referenced in the configuration, then the
/// configuration can still be reloaded.
pub fn changeConditionalState(
    self: *const Config,
    new: conditional.State,
) !?Config {
    // If the conditional state between the old and new is the same,
    // then we don't need to do anything.
    relevant: {
        inline for (@typeInfo(conditional.Key).Enum.fields) |field| {
            const key: conditional.Key = @field(conditional.Key, field.name);

            // Conditional set contains the keys that this config uses. So we
            // only continue if we use this key.
            if (self._conditional_set.contains(key) and !equalField(
                @TypeOf(@field(self._conditional_state, field.name)),
                @field(self._conditional_state, field.name),
                @field(new, field.name),
            )) {
                break :relevant;
            }
        }

        // If we got here, then we didn't find any differences between
        // the old and new conditional state that would affect the
        // configuration.
        return null;
    }

    // Create our new configuration
    const alloc_gpa = self._arena.?.child_allocator;
    var new_config = try self.cloneEmpty(alloc_gpa);
    errdefer new_config.deinit();

    // Set our conditional state so the replay below can use it
    new_config._conditional_state = new;

    // Replay all of our steps to rebuild the configuration
    var it = Replay.iterator(self._replay_steps.items, &new_config);
    try new_config.loadIter(alloc_gpa, &it);
    try new_config.finalize();

    return new_config;
}

/// Expand the relative paths in config-files to be absolute paths
/// relative to the base directory.
fn expandPaths(self: *Config, base: []const u8) !void {
    const arena_alloc = self._arena.?.allocator();

    // Keep track of this step for replays
    try self._replay_steps.append(
        arena_alloc,
        .{ .expand = try arena_alloc.dupe(u8, base) },
    );

    // Expand all of our paths
    inline for (@typeInfo(Config).Struct.fields) |field| {
        if (field.type == RepeatablePath) {
            try @field(self, field.name).expand(
                arena_alloc,
                base,
                &self._diagnostics,
            );
        }
    }
}

fn loadTheme(self: *Config, theme: Theme) !void {
    // Load the correct theme depending on the conditional state.
    // Dark/light themes were programmed prior to conditional configuration
    // so when we introduce that we probably want to replace this.
    const name: []const u8 = switch (self._conditional_state.theme) {
        .light => theme.light,
        .dark => theme.dark,
    };

    // Find our theme file and open it. See the open function for details.
    const themefile = (try themepkg.open(
        self._arena.?.allocator(),
        name,
        &self._diagnostics,
    )) orelse return;
    const path = themefile.path;
    const file = themefile.file;
    defer file.close();

    // From this point onwards, we load the theme and do a bit of a dance
    // to achieve two separate goals:
    //
    //   (1) We want the theme to be loaded and our existing config to
    //       override the theme. So we need to load the theme and apply
    //       our config on top of it.
    //
    //   (2) We want to free existing memory that we aren't using anymore
    //       as a result of reloading the configuration.
    //
    // Point 2 is strictly a result of aur approach to point 1, but it is
    // a nice property to have to limit memory bloat as much as possible.

    // Load into a new configuration so that we can free the existing memory.
    const alloc_gpa = self._arena.?.child_allocator;
    var new_config = try self.cloneEmpty(alloc_gpa);
    errdefer new_config.deinit();

    // Load our theme
    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();
    const Iter = cli.args.LineIterator(@TypeOf(reader));
    var iter: Iter = .{ .r = reader, .filepath = path };
    try new_config.loadIter(alloc_gpa, &iter);

    // Setup our replay to be conditional.
    conditional: for (new_config._replay_steps.items) |*item| {
        switch (item.*) {
            .expand => {},

            // If we see "-e" then we do NOT make the following arguments
            // conditional since they are supposed to be part of the
            // initial command.
            .@"-e" => break :conditional,

            // Change our arg to be conditional on our theme.
            .arg => |v| {
                const alloc_arena = new_config._arena.?.allocator();
                const conds = try alloc_arena.alloc(Conditional, 1);
                conds[0] = .{
                    .key = .theme,
                    .op = .eq,
                    .value = @tagName(self._conditional_state.theme),
                };
                item.* = .{ .conditional_arg = .{
                    .conditions = conds,
                    .arg = v,
                } };
            },

            .conditional_arg => |v| {
                const alloc_arena = new_config._arena.?.allocator();
                const conds = try alloc_arena.alloc(Conditional, v.conditions.len + 1);
                conds[0] = .{
                    .key = .theme,
                    .op = .eq,
                    .value = @tagName(self._conditional_state.theme),
                };
                @memcpy(conds[1..], v.conditions);
                item.* = .{ .conditional_arg = .{
                    .conditions = conds,
                    .arg = v.arg,
                } };
            },
        }
    }

    // Replay our previous inputs so that we can override values
    // from the theme.
    var slice_it = Replay.iterator(self._replay_steps.items, &new_config);
    try new_config.loadIter(alloc_gpa, &slice_it);

    // Success, swap our new config in and free the old.
    self.deinit();
    self.* = new_config;
}

/// Call this once after you are done setting configuration. This
/// is idempotent but will waste memory if called multiple times.
pub fn finalize(self: *Config) !void {
    // We always load the theme first because it may set other fields
    // in our config.
    if (self.theme) |theme| {
        const different = !std.mem.eql(u8, theme.light, theme.dark);

        // Warning: loadTheme will deinit our existing config and replace
        // it so all memory from self prior to this point will be freed.
        try self.loadTheme(theme);

        // If we have different light vs dark mode themes, disable
        // window-theme = auto since that breaks it.
        if (different) {
            // This setting doesn't make sense with different light/dark themes
            // because it'll force the theme based on the Ghostty theme.
            if (self.@"window-theme" == .auto) self.@"window-theme" = .system;

            // Mark that we use a conditional theme
            self._conditional_set.insert(.theme);
        }
    }

    const alloc = self._arena.?.allocator();

    // If we have a font-family set and don't set the others, default
    // the others to the font family. This way, if someone does
    // --font-family=foo, then we try to get the stylized versions of
    // "foo" as well.
    if (self.@"font-family".count() > 0) {
        const fields = &[_][]const u8{
            "font-family-bold",
            "font-family-italic",
            "font-family-bold-italic",
        };
        inline for (fields) |field| {
            if (@field(self, field).count() == 0) {
                @field(self, field) = try self.@"font-family".clone(alloc);
            }
        }
    }

    // Prevent setting TERM to an empty string
    if (self.term.len == 0) {
        // HACK: See comment above at definition
        self.term = "xterm-ghostty";
    }

    // The default for the working directory depends on the system.
    const wd = self.@"working-directory" orelse wd: {
        // If we have no working directory set, our default depends on
        // whether we were launched from the desktop or CLI.
        if (internal_os.launchedFromDesktop()) {
            break :wd "home";
        }

        break :wd "inherit";
    };

    // If we are missing either a command or home directory, we need
    // to look up defaults which is kind of expensive. We only do this
    // on desktop.
    const wd_home = std.mem.eql(u8, "home", wd);
    if ((comptime !builtin.target.isWasm()) and
        (comptime !builtin.is_test))
    {
        if (self.command == null or wd_home) command: {
            // First look up the command using the SHELL env var if needed.
            // We don't do this in flatpak because SHELL in Flatpak is always
            // set to /bin/sh.
            if (self.command) |cmd|
                log.info("shell src=config value={s}", .{cmd})
            else shell_env: {
                // Flatpak always gets its shell from outside the sandbox
                if (internal_os.isFlatpak()) break :shell_env;

                // If we were launched from the desktop, our SHELL env var
                // will represent our SHELL at login time. We want to use the
                // latest shell from /etc/passwd or directory services.
                if (internal_os.launchedFromDesktop()) break :shell_env;

                if (std.process.getEnvVarOwned(alloc, "SHELL")) |value| {
                    log.info("default shell source=env value={s}", .{value});
                    self.command = value;

                    // If we don't need the working directory, then we can exit now.
                    if (!wd_home) break :command;
                } else |_| {}
            }

            switch (builtin.os.tag) {
                .windows => {
                    if (self.command == null) {
                        log.warn("no default shell found, will default to using cmd", .{});
                        self.command = "cmd.exe";
                    }

                    if (wd_home) {
                        var buf: [std.fs.max_path_bytes]u8 = undefined;
                        if (try internal_os.home(&buf)) |home| {
                            self.@"working-directory" = try alloc.dupe(u8, home);
                        }
                    }
                },

                else => {
                    // We need the passwd entry for the remainder
                    const pw = try internal_os.passwd.get(alloc);
                    if (self.command == null) {
                        if (pw.shell) |sh| {
                            log.info("default shell src=passwd value={s}", .{sh});
                            self.command = sh;
                        }
                    }

                    if (wd_home) {
                        if (pw.home) |home| {
                            log.info("default working directory src=passwd value={s}", .{home});
                            self.@"working-directory" = home;
                        }
                    }

                    if (self.command == null) {
                        log.warn("no default shell found, will default to using sh", .{});
                    }
                },
            }
        }
    }

    // If we have the special value "inherit" then set it to null which
    // does the same. In the future we should change to a tagged union.
    if (std.mem.eql(u8, wd, "inherit")) self.@"working-directory" = null;

    // Default our click interval
    if (self.@"click-repeat-interval" == 0 and
        (comptime !builtin.is_test))
    {
        self.@"click-repeat-interval" = internal_os.clickInterval() orelse 500;
    }

    // Clamp our mouse scroll multiplier
    self.@"mouse-scroll-multiplier" = @min(10_000.0, @max(0.01, self.@"mouse-scroll-multiplier"));

    // Clamp our split opacity
    self.@"unfocused-split-opacity" = @min(1.0, @max(0.15, self.@"unfocused-split-opacity"));

    // Clamp our contrast
    self.@"minimum-contrast" = @min(21, @max(1, self.@"minimum-contrast"));

    // Minimmum window size
    if (self.@"window-width" > 0) self.@"window-width" = @max(10, self.@"window-width");
    if (self.@"window-height" > 0) self.@"window-height" = @max(4, self.@"window-height");

    // If URLs are disabled, cut off the first link. The first link is
    // always the URL matcher.
    if (!self.@"link-url") self.link.links.items = self.link.links.items[1..];

    // We warn when the quit-after-last-window-closed-delay is set to a very
    // short value because it can cause Ghostty to quit before the first
    // window is even shown.
    if (self.@"quit-after-last-window-closed-delay") |duration| {
        if (duration.duration < 5 * std.time.ns_per_s) {
            log.warn(
                "quit-after-last-window-closed-delay is set to a very short value ({}), which might cause problems",
                .{duration},
            );
        }
    }

    // We can't set this as a struct default because our config is
    // loaded in environments where a build config isn't available.
    if (self.@"auto-update-channel" == null) {
        self.@"auto-update-channel" = build_config.release_channel;
    }
}

/// Callback for src/cli/args.zig to allow us to handle special cases
/// like `--help` or `-e`. Returns "false" if the CLI parsing should halt.
pub fn parseManuallyHook(
    self: *Config,
    alloc: Allocator,
    arg: []const u8,
    iter: anytype,
) !bool {
    if (std.mem.eql(u8, arg, "-e")) {
        // Add the special -e marker. This prevents:
        // (1) config-file from adding args to the end (see #2908)
        // (2) dark/light theme from making this conditional
        try self._replay_steps.append(alloc, .@"-e");

        // Build up the command. We don't clean this up because we take
        // ownership in our allocator.
        var command = std.ArrayList(u8).init(alloc);
        errdefer command.deinit();

        while (iter.next()) |param| {
            try self._replay_steps.append(alloc, .{ .arg = try alloc.dupe(u8, param) });
            try command.appendSlice(param);
            try command.append(' ');
        }

        if (command.items.len == 0) {
            try self._diagnostics.append(alloc, .{
                .location = try cli.Location.fromIter(iter, alloc),
                .message = try std.fmt.allocPrintZ(
                    alloc,
                    "missing command after {s}",
                    .{arg},
                ),
            });

            return false;
        }

        self.@"initial-command" = command.items[0 .. command.items.len - 1];

        // See "command" docs for the implied configurations and why.
        self.@"gtk-single-instance" = .false;
        self.@"quit-after-last-window-closed" = true;
        self.@"quit-after-last-window-closed-delay" = null;
        if (self.@"shell-integration" != .none) {
            self.@"shell-integration" = .detect;
        }

        // Do not continue, we consumed everything.
        return false;
    }

    // Keep track of our input args for replay
    try self._replay_steps.append(
        alloc,
        .{ .arg = try alloc.dupe(u8, arg) },
    );

    // If we didn't find a special case, continue parsing normally
    return true;
}

/// Create a shallow copy of this config. This will share all the memory
/// allocated with the previous config but will have a new arena for
/// any changes or new allocations. The config should have `deinit`
/// called when it is complete.
///
/// Beware: these shallow clones are not meant for a long lifetime,
/// they are just meant to exist temporarily for the duration of some
/// modifications. It is very important that the original config not
/// be deallocated while shallow clones exist.
pub fn shallowClone(self: *const Config, alloc_gpa: Allocator) Config {
    var result = self.*;
    result._arena = ArenaAllocator.init(alloc_gpa);
    return result;
}

/// Create a copy of the metadata of this configuration but without
/// the actual values. Metadata includes conditional state.
pub fn cloneEmpty(
    self: *const Config,
    alloc_gpa: Allocator,
) Allocator.Error!Config {
    var result = try default(alloc_gpa);
    result._conditional_state = self._conditional_state;
    return result;
}

/// Create a copy of this configuration.
///
/// This will not re-read referenced configuration files and operates
/// purely in-memory.
pub fn clone(
    self: *const Config,
    alloc_gpa: Allocator,
) Allocator.Error!Config {
    // Start with an empty config
    var result = try self.cloneEmpty(alloc_gpa);
    errdefer result.deinit();
    const alloc_arena = result._arena.?.allocator();

    // Copy our values
    inline for (@typeInfo(Config).Struct.fields) |field| {
        if (!@hasField(Key, field.name)) continue;
        @field(result, field.name) = try cloneValue(
            alloc_arena,
            field.type,
            @field(self, field.name),
        );
    }

    // Copy our diagnostics
    result._diagnostics = try self._diagnostics.clone(alloc_arena);

    // Preserve our replay steps. We copy them exactly to also preserve
    // the exact conditionals required for some steps.
    try result._replay_steps.ensureTotalCapacity(
        alloc_arena,
        self._replay_steps.items.len,
    );
    for (self._replay_steps.items) |item| {
        result._replay_steps.appendAssumeCapacity(
            try item.clone(alloc_arena),
        );
    }
    assert(result._replay_steps.items.len == self._replay_steps.items.len);

    // Copy the conditional set
    result._conditional_set = self._conditional_set;

    return result;
}

fn cloneValue(
    alloc: Allocator,
    comptime T: type,
    src: T,
) Allocator.Error!T {
    // Do known named types first
    switch (T) {
        []const u8 => return try alloc.dupe(u8, src),
        [:0]const u8 => return try alloc.dupeZ(u8, src),

        else => {},
    }

    // If we're a type that can have decls and we have clone, then
    // call clone and be done.
    const t = @typeInfo(T);
    if (t == .Struct or t == .Enum or t == .Union) {
        if (@hasDecl(T, "clone")) return try src.clone(alloc);
    }

    // Back into types of types
    switch (t) {
        inline .Bool,
        .Int,
        .Float,
        .Enum,
        .Union,
        => return src,

        .Optional => |info| return try cloneValue(
            alloc,
            info.child,
            src orelse return null,
        ),

        .Struct => |info| {
            // Packed structs we can return directly as copies.
            assert(info.layout == .@"packed");
            return src;
        },

        else => {
            @compileLog(T);
            @compileError("unsupported field type");
        },
    }
}

/// Returns an iterator that goes through each changed field from
/// old to new. The order of old or new do not matter.
pub fn changeIterator(old: *const Config, new: *const Config) ChangeIterator {
    return .{
        .old = old,
        .new = new,
    };
}

/// Returns true if the given key has changed from old to new. This
/// requires the key to be comptime known to make this more efficient.
pub fn changed(self: *const Config, new: *const Config, comptime key: Key) bool {
    // Get the field at comptime
    const field = comptime field: {
        const fields = std.meta.fields(Config);
        for (fields) |field| {
            if (@field(Key, field.name) == key) {
                break :field field;
            }
        }

        unreachable;
    };

    const old_value = @field(self, field.name);
    const new_value = @field(new, field.name);
    return !equalField(field.type, old_value, new_value);
}

/// This yields a key for every changed field between old and new.
pub const ChangeIterator = struct {
    old: *const Config,
    new: *const Config,
    i: usize = 0,

    pub fn next(self: *ChangeIterator) ?Key {
        const fields = comptime std.meta.fields(Key);
        while (self.i < fields.len) {
            switch (self.i) {
                inline 0...(fields.len - 1) => |i| {
                    const field = fields[i];
                    const key = @field(Key, field.name);
                    self.i += 1;
                    if (self.old.changed(self.new, key)) return key;
                },

                else => unreachable,
            }
        }

        return null;
    }
};

/// A config-specific helper to determine if two values of the same
/// type are equal. This isn't the same as std.mem.eql or std.testing.equals
/// because we expect structs to implement their own equality.
///
/// This also doesn't support ALL Zig types, because we only add to it
/// as we need types for the config.
fn equalField(comptime T: type, old: T, new: T) bool {
    // Do known named types first
    switch (T) {
        inline []const u8,
        [:0]const u8,
        => return std.mem.eql(u8, old, new),

        else => {},
    }

    // Back into types of types
    switch (@typeInfo(T)) {
        .Void => return true,

        inline .Bool,
        .Int,
        .Float,
        .Enum,
        => return old == new,

        .Optional => |info| {
            if (old == null and new == null) return true;
            if (old == null or new == null) return false;
            return equalField(info.child, old.?, new.?);
        },

        .Struct => |info| {
            if (@hasDecl(T, "equal")) return old.equal(new);

            // If a struct doesn't declare an "equal" function, we fall back
            // to a recursive field-by-field compare.
            inline for (info.fields) |field_info| {
                if (!equalField(
                    field_info.type,
                    @field(old, field_info.name),
                    @field(new, field_info.name),
                )) return false;
            }
            return true;
        },

        .Union => |info| {
            const tag_type = info.tag_type.?;
            const old_tag = std.meta.activeTag(old);
            const new_tag = std.meta.activeTag(new);
            if (old_tag != new_tag) return false;

            inline for (info.fields) |field_info| {
                if (@field(tag_type, field_info.name) == old_tag) {
                    return equalField(
                        field_info.type,
                        @field(old, field_info.name),
                        @field(new, field_info.name),
                    );
                }
            }

            unreachable;
        },

        else => {
            @compileLog(T);
            @compileError("unsupported field type");
        },
    }
}

/// This is used to "replay" the configuration. See loadTheme for details.
const Replay = struct {
    const Step = union(enum) {
        /// An argument to parse as if it came from the CLI or file.
        arg: []const u8,

        /// A base path to expand relative paths against.
        expand: []const u8,

        /// A conditional argument. This arg is parsed only if all
        /// conditions match (an "AND"). An "OR" can be achieved by
        /// having multiple conditional arg entries.
        conditional_arg: struct {
            conditions: []const Conditional,
            arg: []const u8,
        },

        /// The start of a "-e" argument. This marks the end of
        /// traditional configuration and the beginning of the
        /// "-e" initial command magic. This is separate from "arg"
        /// because there are some behaviors unique to this (i.e.
        /// we want to keep this at the end for config-file).
        ///
        /// Note: when "-e" is used, ONLY this is present and
        /// not an additional "arg" with "-e" value.
        @"-e",

        fn clone(
            self: Step,
            alloc: Allocator,
        ) Allocator.Error!Step {
            return switch (self) {
                .@"-e" => self,
                .arg => |v| .{ .arg = try alloc.dupe(u8, v) },
                .expand => |v| .{ .expand = try alloc.dupe(u8, v) },
                .conditional_arg => |v| conditional: {
                    var conds = try alloc.alloc(Conditional, v.conditions.len);
                    for (v.conditions, 0..) |cond, i| conds[i] = try cond.clone(alloc);
                    break :conditional .{ .conditional_arg = .{
                        .conditions = conds,
                        .arg = try alloc.dupe(u8, v.arg),
                    } };
                },
            };
        }
    };

    const Iterator = struct {
        const Self = @This();

        config: *Config,
        slice: []const Replay.Step,
        idx: usize = 0,

        pub fn next(self: *Self) ?[]const u8 {
            while (true) {
                if (self.idx >= self.slice.len) return null;
                defer self.idx += 1;
                switch (self.slice[self.idx]) {
                    .expand => |base| self.config.expandPaths(base) catch |err| {
                        // This shouldn't happen because to reach this step
                        // means that it succeeded before. Its possible since
                        // expanding paths is a side effect process that the
                        // world state changed and we can't expand anymore.
                        // In that really unfortunate case, we log a warning.
                        log.warn("error expanding paths err={}", .{err});
                    },

                    .conditional_arg => |v| conditional: {
                        // All conditions must match.
                        for (v.conditions) |cond| {
                            if (!self.config._conditional_state.match(cond)) {
                                break :conditional;
                            }
                        }

                        return v.arg;
                    },

                    .arg => |arg| return arg,
                    .@"-e" => return "-e",
                }
            }
        }
    };

    /// Construct a Replay iterator from a slice of replay elements.
    /// This can be used with args.parse and handles intermediate
    /// steps such as expanding relative paths.
    fn iterator(slice: []const Replay.Step, dst: *Config) Iterator {
        return .{ .slice = slice, .config = dst };
    }
};

/// Valid values for custom-shader-animation
/// c_int because it needs to be extern compatible
/// If this is changed, you must also update ghostty.h
pub const CustomShaderAnimation = enum(c_int) {
    false,
    true,
    always,
};

/// Valid values for macos-non-native-fullscreen
/// c_int because it needs to be extern compatible
/// If this is changed, you must also update ghostty.h
pub const NonNativeFullscreen = enum(c_int) {
    false,
    true,
    @"visible-menu",
};

/// Valid values for macos-option-as-alt.
pub const OptionAsAlt = enum {
    false,
    true,
    left,
    right,
};

pub const WindowPaddingColor = enum {
    background,
    extend,
    @"extend-always",
};

/// Color represents a color using RGB.
///
/// This is a packed struct so that the C API to read color values just
/// works by setting it to a C integer.
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// ghostty_config_color_s
    pub const C = extern struct {
        r: u8,
        g: u8,
        b: u8,
    };

    pub fn cval(self: Color) Color.C {
        return .{ .r = self.r, .g = self.g, .b = self.b };
    }

    /// Convert this to the terminal RGB struct
    pub fn toTerminalRGB(self: Color) terminal.color.RGB {
        return .{ .r = self.r, .g = self.g, .b = self.b };
    }

    pub fn parseCLI(input_: ?[]const u8) !Color {
        const input = input_ orelse return error.ValueRequired;

        if (terminal.x11_color.map.get(input)) |rgb| return .{
            .r = rgb.r,
            .g = rgb.g,
            .b = rgb.b,
        };

        return fromHex(input);
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: Color, _: Allocator) error{}!Color {
        return self;
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Color, other: Color) bool {
        return std.meta.eql(self, other);
    }

    /// Used by Formatter
    pub fn formatEntry(self: Color, formatter: anytype) !void {
        var buf: [128]u8 = undefined;
        try formatter.formatEntry(
            []const u8,
            try self.formatBuf(&buf),
        );
    }

    /// Format the color as a string.
    pub fn formatBuf(self: Color, buf: []u8) Allocator.Error![]const u8 {
        return std.fmt.bufPrint(
            buf,
            "#{x:0>2}{x:0>2}{x:0>2}",
            .{ self.r, self.g, self.b },
        ) catch error.OutOfMemory;
    }

    /// fromHex parses a color from a hex value such as #RRGGBB. The "#"
    /// is optional.
    pub fn fromHex(input: []const u8) !Color {
        // Trim the beginning '#' if it exists
        const trimmed = if (input.len != 0 and input[0] == '#') input[1..] else input;

        // We expect exactly 6 for RRGGBB
        if (trimmed.len != 6) return error.InvalidValue;

        // Parse the colors two at a time.
        var result: Color = undefined;
        comptime var i: usize = 0;
        inline while (i < 6) : (i += 2) {
            const v: u8 =
                ((try std.fmt.charToDigit(trimmed[i], 16)) * 16) +
                try std.fmt.charToDigit(trimmed[i + 1], 16);

            @field(result, switch (i) {
                0 => "r",
                2 => "g",
                4 => "b",
                else => unreachable,
            }) = v;
        }

        return result;
    }

    test "fromHex" {
        const testing = std.testing;

        try testing.expectEqual(Color{ .r = 0, .g = 0, .b = 0 }, try Color.fromHex("#000000"));
        try testing.expectEqual(Color{ .r = 10, .g = 11, .b = 12 }, try Color.fromHex("#0A0B0C"));
        try testing.expectEqual(Color{ .r = 10, .g = 11, .b = 12 }, try Color.fromHex("0A0B0C"));
        try testing.expectEqual(Color{ .r = 255, .g = 255, .b = 255 }, try Color.fromHex("FFFFFF"));
    }

    test "parseCLI from name" {
        try std.testing.expectEqual(Color{ .r = 0, .g = 0, .b = 0 }, try Color.parseCLI("black"));
    }

    test "formatConfig" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var color: Color = .{ .r = 10, .g = 11, .b = 12 };
        try color.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = #0a0b0c\n", buf.items);
    }
};

pub const ColorList = struct {
    const Self = @This();

    colors: std.ArrayListUnmanaged(Color) = .{},
    colors_c: std.ArrayListUnmanaged(Color.C) = .{},

    /// ghostty_config_color_list_s
    pub const C = extern struct {
        colors: [*]Color.C,
        len: usize,
    };

    pub fn cval(self: *const Self) C {
        return .{
            .colors = self.colors_c.items.ptr,
            .len = self.colors_c.items.len,
        };
    }

    pub fn parseCLI(
        self: *Self,
        alloc: Allocator,
        input_: ?[]const u8,
    ) !void {
        const input = input_ orelse return error.ValueRequired;
        if (input.len == 0) return error.ValueRequired;

        // Always reset on parse
        self.* = .{};

        // Split the input by commas and parse each color
        var it = std.mem.tokenizeScalar(u8, input, ',');
        var count: usize = 0;
        while (it.next()) |raw| {
            count += 1;
            if (count > 64) return error.InvalidValue;

            const color = try Color.parseCLI(raw);
            try self.colors.append(alloc, color);
            try self.colors_c.append(alloc, color.cval());
        }

        // If no colors were parsed, we need to return an error
        if (self.colors.items.len == 0) return error.InvalidValue;

        assert(self.colors.items.len == self.colors_c.items.len);
    }

    pub fn clone(
        self: *const Self,
        alloc: Allocator,
    ) Allocator.Error!Self {
        return .{
            .colors = try self.colors.clone(alloc),
        };
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        const itemsA = self.colors.items;
        const itemsB = other.colors.items;
        if (itemsA.len != itemsB.len) return false;
        for (itemsA, itemsB) |a, b| {
            if (!a.equal(b)) return false;
        } else return true;
    }

    /// Used by Formatter
    pub fn formatEntry(
        self: Self,
        formatter: anytype,
    ) !void {
        // If no items, we want to render an empty field.
        if (self.colors.items.len == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        // Build up the value of our config. Our buffer size should be
        // sized to contain all possible maximum values.
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        var writer = fbs.writer();
        for (self.colors.items, 0..) |color, i| {
            var color_buf: [128]u8 = undefined;
            const color_str = try color.formatBuf(&color_buf);
            if (i != 0) writer.writeByte(',') catch return error.OutOfMemory;
            writer.writeAll(color_str) catch return error.OutOfMemory;
        }

        try formatter.formatEntry(
            []const u8,
            fbs.getWritten(),
        );
    }

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var p: Self = .{};
        try p.parseCLI(alloc, "black,white");
        try testing.expectEqual(2, p.colors.items.len);

        // Error cases
        try testing.expectError(error.ValueRequired, p.parseCLI(alloc, null));
        try testing.expectError(error.InvalidValue, p.parseCLI(alloc, " "));
    }

    test "format" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var p: Self = .{};
        try p.parseCLI(alloc, "black,white");
        try p.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = #000000,#ffffff\n", buf.items);
    }
};

/// Palette is the 256 color palette for 256-color mode. This is still
/// used by many terminal applications.
pub const Palette = struct {
    const Self = @This();

    /// The actual value that is updated as we parse.
    value: terminal.color.Palette = terminal.color.default,

    pub fn parseCLI(
        self: *Self,
        input: ?[]const u8,
    ) !void {
        const value = input orelse return error.ValueRequired;
        const eqlIdx = std.mem.indexOf(u8, value, "=") orelse
            return error.InvalidValue;

        const key = try std.fmt.parseInt(u8, value[0..eqlIdx], 10);
        const rgb = try Color.parseCLI(value[eqlIdx + 1 ..]);
        self.value[key] = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b };
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: Self, _: Allocator) error{}!Self {
        return self;
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        return std.meta.eql(self, other);
    }

    /// Used by Formatter
    pub fn formatEntry(self: Self, formatter: anytype) !void {
        var buf: [128]u8 = undefined;
        for (0.., self.value) |k, v| {
            try formatter.formatEntry(
                []const u8,
                std.fmt.bufPrint(
                    &buf,
                    "{d}=#{x:0>2}{x:0>2}{x:0>2}",
                    .{ k, v.r, v.g, v.b },
                ) catch return error.OutOfMemory,
            );
        }
    }

    test "parseCLI" {
        const testing = std.testing;

        var p: Self = .{};
        try p.parseCLI("0=#AABBCC");
        try testing.expect(p.value[0].r == 0xAA);
        try testing.expect(p.value[0].g == 0xBB);
        try testing.expect(p.value[0].b == 0xCC);
    }

    test "parseCLI overflow" {
        const testing = std.testing;

        var p: Self = .{};
        try testing.expectError(error.Overflow, p.parseCLI("256=#AABBCC"));
    }

    test "formatConfig" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var list: Self = .{};
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = 0=#1d1f21\n", buf.items[0..14]);
    }
};

/// RepeatableString is a string value that can be repeated to accumulate
/// a list of strings. This isn't called "StringList" because I find that
/// sometimes leads to confusion that it _accepts_ a list such as
/// comma-separated values.
pub const RepeatableString = struct {
    const Self = @This();

    // Allocator for the list is the arena for the parent config.
    list: std.ArrayListUnmanaged([:0]const u8) = .{},

    pub fn parseCLI(self: *Self, alloc: Allocator, input: ?[]const u8) !void {
        const value = input orelse return error.ValueRequired;

        // Empty value resets the list
        if (value.len == 0) {
            self.list.clearRetainingCapacity();
            return;
        }

        const copy = try alloc.dupeZ(u8, value);
        try self.list.append(alloc, copy);
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const Self, alloc: Allocator) Allocator.Error!Self {
        // Copy the list and all the strings in the list.
        var list = try std.ArrayListUnmanaged([:0]const u8).initCapacity(
            alloc,
            self.list.items.len,
        );
        errdefer {
            for (list.items) |item| alloc.free(item);
            list.deinit(alloc);
        }
        for (self.list.items) |item| {
            const copy = try alloc.dupeZ(u8, item);
            list.appendAssumeCapacity(copy);
        }

        return .{ .list = list };
    }

    /// The number of items in the list
    pub fn count(self: Self) usize {
        return self.list.items.len;
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        const itemsA = self.list.items;
        const itemsB = other.list.items;
        if (itemsA.len != itemsB.len) return false;
        for (itemsA, itemsB) |a, b| {
            if (!std.mem.eql(u8, a, b)) return false;
        } else return true;
    }

    /// Used by Formatter
    pub fn formatEntry(self: Self, formatter: anytype) !void {
        // If no items, we want to render an empty field.
        if (self.list.items.len == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        for (self.list.items) |value| {
            try formatter.formatEntry([]const u8, value);
        }
    }

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "A");
        try list.parseCLI(alloc, "B");
        try testing.expectEqual(@as(usize, 2), list.list.items.len);

        try list.parseCLI(alloc, "");
        try testing.expectEqual(@as(usize, 0), list.list.items.len);
    }

    test "formatConfig empty" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var list: Self = .{};
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = \n", buf.items);
    }

    test "formatConfig single item" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "A");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = A\n", buf.items);
    }

    test "formatConfig multiple items" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "A");
        try list.parseCLI(alloc, "B");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = A\na = B\n", buf.items);
    }
};

/// RepeatablePath is like repeatable string but represents a path value.
/// The difference is that when loading the configuration any values for
/// this will be automatically expanded relative to the path of the config
/// file.
pub const RepeatablePath = struct {
    const Self = @This();

    const Path = union(enum) {
        /// No error if the file does not exist.
        optional: [:0]const u8,

        /// The file is required to exist.
        required: [:0]const u8,
    };

    value: std.ArrayListUnmanaged(Path) = .{},

    pub fn parseCLI(self: *Self, alloc: Allocator, input: ?[]const u8) !void {
        const value, const optional = if (input) |value| blk: {
            if (value.len == 0) {
                self.value.clearRetainingCapacity();
                return;
            }

            break :blk if (value[0] == '?')
                .{ value[1..], true }
            else if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"')
                .{ value[1 .. value.len - 1], false }
            else
                .{ value, false };
        } else return error.ValueRequired;

        if (value.len == 0) {
            // This handles the case of zero length paths after removing any ?
            // prefixes or surrounding quotes. In this case, we don't reset the
            // list.
            return;
        }

        const item: Path = if (optional)
            .{ .optional = try alloc.dupeZ(u8, value) }
        else
            .{ .required = try alloc.dupeZ(u8, value) };

        try self.value.append(alloc, item);
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const Self, alloc: Allocator) Allocator.Error!Self {
        const value = try self.value.clone(alloc);
        for (value.items) |*item| {
            switch (item.*) {
                .optional, .required => |*path| path.* = try alloc.dupeZ(u8, path.*),
            }
        }

        return .{
            .value = value,
        };
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        if (self.value.items.len != other.value.items.len) return false;
        for (self.value.items, other.value.items) |a, b| {
            if (!std.meta.eql(a, b)) return false;
        }

        return true;
    }

    /// Used by Formatter
    pub fn formatEntry(self: Self, formatter: anytype) !void {
        if (self.value.items.len == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        var buf: [std.fs.max_path_bytes + 1]u8 = undefined;
        for (self.value.items) |item| {
            const value = switch (item) {
                .optional => |path| std.fmt.bufPrint(
                    &buf,
                    "?{s}",
                    .{path},
                ) catch |err| switch (err) {
                    // Required for builds on Linux where NoSpaceLeft
                    // isn't an allowed error for fmt.
                    error.NoSpaceLeft => return error.OutOfMemory,
                },
                .required => |path| path,
            };

            try formatter.formatEntry([]const u8, value);
        }
    }

    /// Expand all the paths relative to the base directory.
    pub fn expand(
        self: *Self,
        alloc: Allocator,
        base: []const u8,
        diags: *cli.DiagnosticList,
    ) !void {
        assert(std.fs.path.isAbsolute(base));
        var dir = try std.fs.cwd().openDir(base, .{});
        defer dir.close();

        for (0..self.value.items.len) |i| {
            const path = switch (self.value.items[i]) {
                .optional, .required => |path| path,
            };

            // If it is already absolute we can ignore it.
            if (path.len == 0 or std.fs.path.isAbsolute(path)) continue;

            // If it isn't absolute, we need to make it absolute relative
            // to the base.
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const abs = dir.realpath(path, &buf) catch |err| abs: {
                if (err == error.FileNotFound) {
                    // The file doesn't exist. Try to resolve the relative path
                    // another way.
                    const resolved = try std.fs.path.resolve(alloc, &.{ base, path });
                    defer alloc.free(resolved);
                    @memcpy(buf[0..resolved.len], resolved);
                    break :abs buf[0..resolved.len];
                }

                try diags.append(alloc, .{
                    .message = try std.fmt.allocPrintZ(
                        alloc,
                        "error resolving file path {s}: {}",
                        .{ path, err },
                    ),
                });

                // Blank this path so that we don't attempt to resolve it again
                self.value.items[i] = .{ .required = "" };

                continue;
            };

            log.debug(
                "expanding file path relative={s} abs={s}",
                .{ path, abs },
            );

            switch (self.value.items[i]) {
                .optional, .required => |*p| p.* = try alloc.dupeZ(u8, abs),
            }
        }
    }

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "config.1");
        try list.parseCLI(alloc, "?config.2");
        try list.parseCLI(alloc, "\"?config.3\"");

        // Zero-length values, ignored
        try list.parseCLI(alloc, "?");
        try list.parseCLI(alloc, "\"\"");

        try testing.expectEqual(@as(usize, 3), list.value.items.len);

        const Tag = std.meta.Tag(Path);
        try testing.expectEqual(Tag.required, @as(Tag, list.value.items[0]));
        try testing.expectEqualStrings("config.1", list.value.items[0].required);

        try testing.expectEqual(Tag.optional, @as(Tag, list.value.items[1]));
        try testing.expectEqualStrings("config.2", list.value.items[1].optional);

        try testing.expectEqual(Tag.required, @as(Tag, list.value.items[2]));
        try testing.expectEqualStrings("?config.3", list.value.items[2].required);

        try list.parseCLI(alloc, "");
        try testing.expectEqual(@as(usize, 0), list.value.items.len);
    }

    test "formatConfig empty" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var list: Self = .{};
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = \n", buf.items);
    }

    test "formatConfig single item" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "A");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = A\n", buf.items);
    }

    test "formatConfig multiple items" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "A");
        try list.parseCLI(alloc, "?B");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = A\na = ?B\n", buf.items);
    }
};

/// FontVariation is a repeatable configuration value that sets a single
/// font variation value. Font variations are configurations for what
/// are often called "variable fonts." The font files usually end in
/// "-VF.ttf."
///
/// The value for this is in the format of `id=value` where `id` is the
/// 4-character font variation axis identifier and `value` is the
/// floating point value for that axis. For more details on font variations
/// see the MDN font-variation-settings documentation since this copies that
/// behavior almost exactly:
///
/// https://developer.mozilla.org/en-US/docs/Web/CSS/font-variation-settings
pub const RepeatableFontVariation = struct {
    const Self = @This();

    // Allocator for the list is the arena for the parent config.
    list: std.ArrayListUnmanaged(fontpkg.face.Variation) = .{},

    pub fn parseCLI(self: *Self, alloc: Allocator, input_: ?[]const u8) !void {
        const input = input_ orelse return error.ValueRequired;
        const eql_idx = std.mem.indexOf(u8, input, "=") orelse return error.InvalidValue;
        const whitespace = " \t";
        const key = std.mem.trim(u8, input[0..eql_idx], whitespace);
        const value = std.mem.trim(u8, input[eql_idx + 1 ..], whitespace);
        if (key.len != 4) return error.InvalidValue;
        try self.list.append(alloc, .{
            .id = fontpkg.face.Variation.Id.init(@ptrCast(key.ptr)),
            .value = std.fmt.parseFloat(f64, value) catch return error.InvalidValue,
        });
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const Self, alloc: Allocator) Allocator.Error!Self {
        return .{
            .list = try self.list.clone(alloc),
        };
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        const itemsA = self.list.items;
        const itemsB = other.list.items;
        if (itemsA.len != itemsB.len) return false;
        for (itemsA, itemsB) |a, b| {
            if (!std.meta.eql(a, b)) return false;
        } else return true;
    }

    /// Used by Formatter
    pub fn formatEntry(
        self: Self,
        formatter: anytype,
    ) !void {
        if (self.list.items.len == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        var buf: [128]u8 = undefined;
        for (self.list.items) |value| {
            const str = std.fmt.bufPrint(&buf, "{s}={d}", .{
                value.id.str(),
                value.value,
            }) catch return error.OutOfMemory;
            try formatter.formatEntry([]const u8, str);
        }
    }

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "wght=200");
        try list.parseCLI(alloc, "slnt=-15");

        try testing.expectEqual(@as(usize, 2), list.list.items.len);
        try testing.expectEqual(fontpkg.face.Variation{
            .id = fontpkg.face.Variation.Id.init("wght"),
            .value = 200,
        }, list.list.items[0]);
        try testing.expectEqual(fontpkg.face.Variation{
            .id = fontpkg.face.Variation.Id.init("slnt"),
            .value = -15,
        }, list.list.items[1]);
    }

    test "parseCLI with whitespace" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "wght =200");
        try list.parseCLI(alloc, "slnt= -15");

        try testing.expectEqual(@as(usize, 2), list.list.items.len);
        try testing.expectEqual(fontpkg.face.Variation{
            .id = fontpkg.face.Variation.Id.init("wght"),
            .value = 200,
        }, list.list.items[0]);
        try testing.expectEqual(fontpkg.face.Variation{
            .id = fontpkg.face.Variation.Id.init("slnt"),
            .value = -15,
        }, list.list.items[1]);
    }

    test "formatConfig single" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "wght = 200");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = wght=200\n", buf.items);
    }
};

/// Stores a set of keybinds.
pub const Keybinds = struct {
    set: inputpkg.Binding.Set = .{},

    pub fn parseCLI(self: *Keybinds, alloc: Allocator, input: ?[]const u8) !void {
        var copy: ?[]u8 = null;
        const value = value: {
            const value = input orelse return error.ValueRequired;

            // If we don't have a colon, use the value as-is, no copy
            if (std.mem.indexOf(u8, value, ":") == null)
                break :value value;

            // If we have a colon, we copy the whole value for now. We could
            // do this more efficiently later if we wanted to.
            const buf = try alloc.alloc(u8, value.len);
            copy = buf;

            @memcpy(buf, value);
            break :value buf;
        };
        errdefer if (copy) |v| alloc.free(v);

        // Check for special values
        if (std.mem.eql(u8, value, "clear")) {
            // We don't clear the memory because its in the arena and unlikely
            // to be free-able anyways (since arenas can only clear the last
            // allocated value). This isn't a memory leak because the arena
            // will be freed when the config is freed.
            log.info("config has 'keybind = clear', all keybinds cleared", .{});
            self.set = .{};
            return;
        }

        // Let our much better tested binding package handle parsing and storage.
        try self.set.parseAndPut(alloc, value);
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const Keybinds, alloc: Allocator) Allocator.Error!Keybinds {
        return .{ .set = try self.set.clone(alloc) };
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Keybinds, other: Keybinds) bool {
        return equalSet(&self.set, &other.set);
    }

    fn equalSet(
        self: *const inputpkg.Binding.Set,
        other: *const inputpkg.Binding.Set,
    ) bool {
        // Two keybinds are considered equal if their primary bindings
        // are the same. We don't compare reverse mappings and such.
        const self_map = &self.bindings;
        const other_map = &other.bindings;

        // If the count of mappings isn't identical they can't be equal
        if (self_map.count() != other_map.count()) return false;

        var it = self_map.iterator();
        while (it.next()) |self_entry| {
            // If the trigger isn't in the other map, they can't be equal
            const other_entry = other_map.getEntry(self_entry.key_ptr.*) orelse
                return false;

            // If the entry types are different, they can't be equal
            if (std.meta.activeTag(self_entry.value_ptr.*) !=
                std.meta.activeTag(other_entry.value_ptr.*)) return false;

            switch (self_entry.value_ptr.*) {
                // They're equal if both leader sets are equal.
                .leader => if (!equalSet(
                    self_entry.value_ptr.*.leader,
                    other_entry.value_ptr.*.leader,
                )) return false,

                // Actions are compared by field directly
                .leaf => {
                    const self_leaf = self_entry.value_ptr.*.leaf;
                    const other_leaf = other_entry.value_ptr.*.leaf;

                    if (!equalField(
                        inputpkg.Binding.Set.Leaf,
                        self_leaf,
                        other_leaf,
                    )) return false;
                },
            }
        }

        return true;
    }

    /// Like formatEntry but has an option to include docs.
    pub fn formatEntryDocs(self: Keybinds, formatter: anytype, docs: bool) !void {
        if (self.set.bindings.size == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        var buf: [1024]u8 = undefined;
        var iter = self.set.bindings.iterator();
        while (iter.next()) |next| {
            const k = next.key_ptr.*;
            const v = next.value_ptr.*;
            if (docs) {
                try formatter.writer.writeAll("\n");
                const name = @tagName(v);
                inline for (@typeInfo(help_strings.KeybindAction).Struct.decls) |decl| {
                    if (std.mem.eql(u8, decl.name, name)) {
                        const help = @field(help_strings.KeybindAction, decl.name);
                        try formatter.writer.writeAll("# " ++ decl.name ++ "\n");
                        var lines = std.mem.splitScalar(u8, help, '\n');
                        while (lines.next()) |line| {
                            try formatter.writer.writeAll("#   ");
                            try formatter.writer.writeAll(line);
                            try formatter.writer.writeAll("\n");
                        }
                        break;
                    }
                }
            }

            var buffer_stream = std.io.fixedBufferStream(&buf);
            std.fmt.format(buffer_stream.writer(), "{}", .{k}) catch return error.OutOfMemory;
            try v.formatEntries(&buffer_stream, formatter);
        }
    }

    /// Used by Formatter
    pub fn formatEntry(self: Keybinds, formatter: anytype) !void {
        try self.formatEntryDocs(formatter, false);
    }

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var set: Keybinds = .{};
        try set.parseCLI(alloc, "shift+a=copy_to_clipboard");
        try set.parseCLI(alloc, "shift+a=csi:hello");
    }

    test "formatConfig single" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Keybinds = .{};
        try list.parseCLI(alloc, "shift+a=csi:hello");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = shift+a=csi:hello\n", buf.items);
    }

    // Regression test for https://github.com/ghostty-org/ghostty/issues/2734
    test "formatConfig multiple items" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Keybinds = .{};
        try list.parseCLI(alloc, "ctrl+z>1=goto_tab:1");
        try list.parseCLI(alloc, "ctrl+z>2=goto_tab:2");
        try list.formatEntry(formatterpkg.entryFormatter("keybind", buf.writer()));

        const want =
            \\keybind = ctrl+z>1=goto_tab:1
            \\keybind = ctrl+z>2=goto_tab:2
            \\
        ;
        try std.testing.expectEqualStrings(want, buf.items);
    }

    test "formatConfig multiple items nested" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Keybinds = .{};
        try list.parseCLI(alloc, "ctrl+a>ctrl+b>n=new_window");
        try list.parseCLI(alloc, "ctrl+a>ctrl+b>w=close_window");
        try list.parseCLI(alloc, "ctrl+a>ctrl+c>t=new_tab");
        try list.parseCLI(alloc, "ctrl+b>ctrl+d>a=previous_tab");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));

        // NB: This does not currently retain the order of the keybinds.
        const want =
            \\a = ctrl+a>ctrl+b>w=close_window
            \\a = ctrl+a>ctrl+b>n=new_window
            \\a = ctrl+a>ctrl+c>t=new_tab
            \\a = ctrl+b>ctrl+d>a=previous_tab
            \\
        ;
        try std.testing.expectEqualStrings(want, buf.items);
    }
};

/// See "font-codepoint-map" for documentation.
pub const RepeatableCodepointMap = struct {
    const Self = @This();

    map: fontpkg.CodepointMap = .{},

    pub fn parseCLI(self: *Self, alloc: Allocator, input_: ?[]const u8) !void {
        const input = input_ orelse return error.ValueRequired;
        const eql_idx = std.mem.indexOf(u8, input, "=") orelse return error.InvalidValue;
        const whitespace = " \t";
        const key = std.mem.trim(u8, input[0..eql_idx], whitespace);
        const value = std.mem.trim(u8, input[eql_idx + 1 ..], whitespace);
        const valueZ = try alloc.dupeZ(u8, value);

        var p: UnicodeRangeParser = .{ .input = key };
        while (try p.next()) |range| {
            try self.map.add(alloc, .{
                .range = range,
                .descriptor = .{
                    .family = valueZ,
                    .monospace = false, // we allow any font
                },
            });
        }
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const Self, alloc: Allocator) Allocator.Error!Self {
        return .{ .map = try self.map.clone(alloc) };
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        const itemsA = self.map.list.slice();
        const itemsB = other.map.list.slice();
        if (itemsA.len != itemsB.len) return false;
        for (0..itemsA.len) |i| {
            const a = itemsA.get(i);
            const b = itemsB.get(i);
            if (!std.meta.eql(a, b)) return false;
        } else return true;
    }

    /// Used by Formatter
    pub fn formatEntry(
        self: Self,
        formatter: anytype,
    ) !void {
        if (self.map.list.len == 0) {
            try formatter.formatEntry(void, {});
            return;
        }

        var buf: [1024]u8 = undefined;
        const ranges = self.map.list.items(.range);
        const descriptors = self.map.list.items(.descriptor);
        for (ranges, descriptors) |range, descriptor| {
            if (range[0] == range[1]) {
                try formatter.formatEntry(
                    []const u8,
                    std.fmt.bufPrint(
                        &buf,
                        "U+{X:0>4}={s}",
                        .{
                            range[0],
                            descriptor.family orelse "",
                        },
                    ) catch return error.OutOfMemory,
                );
            } else {
                try formatter.formatEntry(
                    []const u8,
                    std.fmt.bufPrint(
                        &buf,
                        "U+{X:0>4}-U+{X:0>4}={s}",
                        .{
                            range[0],
                            range[1],
                            descriptor.family orelse "",
                        },
                    ) catch return error.OutOfMemory,
                );
            }
        }
    }

    /// Parses the list of Unicode codepoint ranges. Valid syntax:
    ///
    ///   "" (empty returns null)
    ///   U+1234
    ///   U+1234-5678
    ///   U+1234,U+5678
    ///   U+1234-5678,U+5678
    ///   U+1234,U+5678-U+9ABC
    ///
    /// etc.
    const UnicodeRangeParser = struct {
        input: []const u8,
        i: usize = 0,

        pub fn next(self: *UnicodeRangeParser) !?[2]u21 {
            // Once we're EOF then we're done without an error.
            if (self.eof()) return null;

            // One codepoint no matter what
            const start = try self.parseCodepoint();
            if (self.eof()) return .{ start, start };

            // We're allowed to have any whitespace here
            self.consumeWhitespace();

            // Otherwise we expect either a range or a comma
            switch (self.input[self.i]) {
                // Comma means we have another codepoint but in a different
                // range so we return our current codepoint.
                ',' => {
                    self.advance();
                    self.consumeWhitespace();
                    if (self.eof()) return error.InvalidValue;
                    return .{ start, start };
                },

                // Hyphen means we have a range.
                '-' => {
                    self.advance();
                    self.consumeWhitespace();
                    if (self.eof()) return error.InvalidValue;
                    const end = try self.parseCodepoint();
                    self.consumeWhitespace();
                    if (!self.eof() and self.input[self.i] != ',') return error.InvalidValue;
                    self.advance();
                    self.consumeWhitespace();
                    if (start > end) return error.InvalidValue;
                    return .{ start, end };
                },

                else => return error.InvalidValue,
            }
        }

        fn consumeWhitespace(self: *UnicodeRangeParser) void {
            while (!self.eof()) {
                switch (self.input[self.i]) {
                    ' ', '\t' => self.advance(),
                    else => return,
                }
            }
        }

        fn parseCodepoint(self: *UnicodeRangeParser) !u21 {
            if (self.input[self.i] != 'U') return error.InvalidValue;
            self.advance();
            if (self.eof()) return error.InvalidValue;
            if (self.input[self.i] != '+') return error.InvalidValue;
            self.advance();
            if (self.eof()) return error.InvalidValue;

            const start_i = self.i;
            while (true) {
                const current = self.input[self.i];
                const is_hex = (current >= '0' and current <= '9') or
                    (current >= 'A' and current <= 'F') or
                    (current >= 'a' and current <= 'f');
                if (!is_hex) break;

                // Advance but break on EOF
                self.advance();
                if (self.eof()) break;
            }

            // If we didn't consume a single character, we have an error.
            if (start_i == self.i) return error.InvalidValue;

            return std.fmt.parseInt(u21, self.input[start_i..self.i], 16) catch
                return error.InvalidValue;
        }

        fn advance(self: *UnicodeRangeParser) void {
            self.i += 1;
        }

        fn eof(self: *const UnicodeRangeParser) bool {
            return self.i >= self.input.len;
        }
    };

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "U+ABCD=Comic Sans");
        try list.parseCLI(alloc, "U+0001 - U+0005=Verdana");
        try list.parseCLI(alloc, "U+0006-U+0009, U+ABCD=Courier");

        try testing.expectEqual(@as(usize, 4), list.map.list.len);
        {
            const entry = list.map.list.get(0);
            try testing.expectEqual([2]u21{ 0xABCD, 0xABCD }, entry.range);
            try testing.expectEqualStrings("Comic Sans", entry.descriptor.family.?);
        }
        {
            const entry = list.map.list.get(1);
            try testing.expectEqual([2]u21{ 1, 5 }, entry.range);
            try testing.expectEqualStrings("Verdana", entry.descriptor.family.?);
        }
        {
            const entry = list.map.list.get(2);
            try testing.expectEqual([2]u21{ 6, 9 }, entry.range);
            try testing.expectEqualStrings("Courier", entry.descriptor.family.?);
        }
        {
            const entry = list.map.list.get(3);
            try testing.expectEqual([2]u21{ 0xABCD, 0xABCD }, entry.range);
            try testing.expectEqualStrings("Courier", entry.descriptor.family.?);
        }
    }

    test "formatConfig single" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "U+ABCD=Comic Sans");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = U+ABCD=Comic Sans\n", buf.items);
    }

    test "formatConfig range" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "U+0001 - U+0005=Verdana");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = U+0001-U+0005=Verdana\n", buf.items);
    }

    test "formatConfig multiple" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var list: Self = .{};
        try list.parseCLI(alloc, "U+0006-U+0009, U+ABCD=Courier");
        try list.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8,
            \\a = U+0006-U+0009=Courier
            \\a = U+ABCD=Courier
            \\
        , buf.items);
    }
};

pub const FontStyle = union(enum) {
    const Self = @This();

    /// Use the default font style that font discovery finds.
    default: void,

    /// Disable this font style completely. This will fall back to using
    /// the regular font when this style is encountered.
    false: void,

    /// A specific named font style to use for this style.
    name: [:0]const u8,

    pub fn parseCLI(self: *Self, alloc: Allocator, input: ?[]const u8) !void {
        const value = input orelse return error.ValueRequired;

        if (std.mem.eql(u8, value, "default")) {
            self.* = .{ .default = {} };
            return;
        }

        if (std.mem.eql(u8, value, "false")) {
            self.* = .{ .false = {} };
            return;
        }

        const nameZ = try alloc.dupeZ(u8, value);
        self.* = .{ .name = nameZ };
    }

    /// Returns the string name value that can be used with a font
    /// descriptor.
    pub fn nameValue(self: Self) ?[:0]const u8 {
        return switch (self) {
            .default, .false => null,
            .name => self.name,
        };
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: Self, alloc: Allocator) Allocator.Error!Self {
        return switch (self) {
            .default, .false => self,
            .name => |v| .{ .name = try alloc.dupeZ(u8, v) },
        };
    }

    /// Used by Formatter
    pub fn formatEntry(self: Self, formatter: anytype) !void {
        switch (self) {
            .default, .false => try formatter.formatEntry(
                []const u8,
                @tagName(self),
            ),

            .name => |name| {
                try formatter.formatEntry([:0]const u8, name);
            },
        }
    }

    test "parseCLI" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var p: Self = .{ .default = {} };
        try p.parseCLI(alloc, "default");
        try testing.expectEqual(Self{ .default = {} }, p);

        try p.parseCLI(alloc, "false");
        try testing.expectEqual(Self{ .false = {} }, p);

        try p.parseCLI(alloc, "bold");
        try testing.expectEqualStrings("bold", p.name);
    }

    test "formatConfig default" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var p: Self = .{ .default = {} };
        try p.parseCLI(alloc, "default");
        try p.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = default\n", buf.items);
    }

    test "formatConfig false" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var p: Self = .{ .default = {} };
        try p.parseCLI(alloc, "false");
        try p.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = false\n", buf.items);
    }

    test "formatConfig named" {
        const testing = std.testing;
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();

        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var p: Self = .{ .default = {} };
        try p.parseCLI(alloc, "bold");
        try p.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
        try std.testing.expectEqualSlices(u8, "a = bold\n", buf.items);
    }
};

/// See `font-synthetic-style` for documentation.
pub const FontSyntheticStyle = packed struct {
    bold: bool = true,
    italic: bool = true,
    @"bold-italic": bool = true,
};

/// See "link" for documentation.
pub const RepeatableLink = struct {
    const Self = @This();

    links: std.ArrayListUnmanaged(inputpkg.Link) = .{},

    pub fn parseCLI(self: *Self, alloc: Allocator, input_: ?[]const u8) !void {
        _ = self;
        _ = alloc;
        _ = input_;
        return error.NotImplemented;
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(
        self: *const Self,
        alloc: Allocator,
    ) Allocator.Error!Self {
        // Note: we don't do any errdefers below since the allocation
        // is expected to be arena allocated.

        var list = try std.ArrayListUnmanaged(inputpkg.Link).initCapacity(
            alloc,
            self.links.items.len,
        );
        for (self.links.items) |item| {
            const copy = try item.clone(alloc);
            list.appendAssumeCapacity(copy);
        }

        return .{ .links = list };
    }

    /// Compare if two of our value are requal. Required by Config.
    pub fn equal(self: Self, other: Self) bool {
        const itemsA = self.links.items;
        const itemsB = other.links.items;
        if (itemsA.len != itemsB.len) return false;
        for (itemsA, itemsB) |*a, *b| {
            if (!a.equal(b)) return false;
        } else return true;
    }

    /// Used by Formatter
    pub fn formatEntry(self: Self, formatter: anytype) !void {
        // This currently can't be set so we don't format anything.
        _ = self;
        _ = formatter;
    }
};

/// Options for copy on select behavior.
pub const CopyOnSelect = enum {
    /// Disables copy on select entirely.
    false,

    /// Copy on select is enabled, but goes to the selection clipboard.
    /// This is not supported on platforms such as macOS. This is the default.
    true,

    /// Copy on select is enabled and goes to both the system clipboard
    /// and the selection clipboard (for Linux).
    clipboard,
};

/// Shell integration values
pub const ShellIntegration = enum {
    none,
    detect,
    bash,
    elvish,
    fish,
    zsh,
};

/// Shell integration features
pub const ShellIntegrationFeatures = packed struct {
    cursor: bool = true,
    sudo: bool = false,
    title: bool = true,
};

/// OSC 4, 10, 11, and 12 default color reporting format.
pub const OSCColorReportFormat = enum {
    none,
    @"8-bit",
    @"16-bit",
};

/// The default window theme.
pub const WindowTheme = enum {
    auto,
    system,
    light,
    dark,
    ghostty,
};

/// See window-colorspace
pub const WindowColorspace = enum {
    srgb,
    @"display-p3",
};

/// See macos-titlebar-style
pub const MacTitlebarStyle = enum {
    native,
    transparent,
    tabs,
    hidden,
};

/// See macos-titlebar-proxy-icon
pub const MacTitlebarProxyIcon = enum {
    visible,
    hidden,
};

/// See macos-icon
///
/// Note: future versions of Ghostty can support a custom icon with
/// path by changing this to a tagged union, which doesn't change our
/// format at all.
pub const MacAppIcon = enum {
    official,
    @"custom-style",
};

/// See macos-icon-frame
pub const MacAppIconFrame = enum {
    aluminum,
    beige,
    plastic,
    chrome,
};

/// See gtk-single-instance
pub const GtkSingleInstance = enum {
    desktop,
    false,
    true,
};

/// See gtk-tabs-location
pub const GtkTabsLocation = enum {
    top,
    bottom,
    left,
    right,
    hidden,
};

/// See adw-toolbar-style
pub const AdwToolbarStyle = enum {
    flat,
    raised,
    @"raised-border",
};

/// See mouse-shift-capture
pub const MouseShiftCapture = enum {
    false,
    true,
    always,
    never,
};

/// How to treat requests to write to or read from the clipboard
pub const ClipboardAccess = enum {
    allow,
    deny,
    ask,
};

/// See window-save-state
pub const WindowSaveState = enum {
    default,
    never,
    always,
};

/// See window-new-tab-position
pub const WindowNewTabPosition = enum {
    current,
    end,
};

/// See resize-overlay
pub const ResizeOverlay = enum {
    always,
    never,
    @"after-first",
};

/// See resize-overlay-position
pub const ResizeOverlayPosition = enum {
    center,
    @"top-left",
    @"top-center",
    @"top-right",
    @"bottom-left",
    @"bottom-center",
    @"bottom-right",
};

/// See quick-terminal-position
pub const QuickTerminalPosition = enum {
    top,
    bottom,
    left,
    right,
    center,
};

/// See quick-terminal-screen
pub const QuickTerminalScreen = enum {
    main,
    mouse,
    @"macos-menu-bar",
};

/// See grapheme-width-method
pub const GraphemeWidthMethod = enum {
    legacy,
    unicode,
};

/// See freetype-load-flag
pub const FreetypeLoadFlags = packed struct {
    // The defaults here at the time of writing this match the defaults
    // for Freetype itself. Ghostty hasn't made any opinionated changes
    // to these defaults.
    hinting: bool = true,
    @"force-autohint": bool = true,
    monochrome: bool = true,
    autohint: bool = true,
};

/// See linux-cgroup
pub const LinuxCgroup = enum {
    never,
    always,
    @"single-instance",
};

/// See auto-updates
pub const AutoUpdate = enum {
    off,
    check,
    download,
};

/// See theme
pub const Theme = struct {
    light: []const u8,
    dark: []const u8,

    pub fn parseCLI(self: *Theme, alloc: Allocator, input_: ?[]const u8) !void {
        const input = input_ orelse return error.ValueRequired;
        if (input.len == 0) return error.ValueRequired;

        // If there is a comma, equal sign, or colon, then we assume that
        // we're parsing a light/dark mode theme pair. Note that "=" isn't
        // actually valid for setting a light/dark mode pair but I anticipate
        // it'll be a common typo.
        if (std.mem.indexOf(u8, input, ",") != null or
            std.mem.indexOf(u8, input, "=") != null or
            std.mem.indexOf(u8, input, ":") != null)
        {
            self.* = try cli.args.parseAutoStruct(
                Theme,
                alloc,
                input,
            );
            return;
        }

        // Trim our value
        const trimmed = std.mem.trim(u8, input, cli.args.whitespace);

        // Set the value to the specified value directly.
        self.* = .{
            .light = try alloc.dupeZ(u8, trimmed),
            .dark = self.light,
        };
    }

    /// Deep copy of the struct. Required by Config.
    pub fn clone(self: *const Theme, alloc: Allocator) Allocator.Error!Theme {
        return .{
            .light = try alloc.dupeZ(u8, self.light),
            .dark = try alloc.dupeZ(u8, self.dark),
        };
    }

    /// Used by Formatter
    pub fn formatEntry(
        self: Theme,
        formatter: anytype,
    ) !void {
        var buf: [4096]u8 = undefined;
        if (std.mem.eql(u8, self.light, self.dark)) {
            try formatter.formatEntry([]const u8, self.light);
            return;
        }

        const str = std.fmt.bufPrint(&buf, "light:{s},dark:{s}", .{
            self.light,
            self.dark,
        }) catch return error.OutOfMemory;
        try formatter.formatEntry([]const u8, str);
    }

    test "parse Theme" {
        const testing = std.testing;
        var arena = ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        // Single
        {
            var v: Theme = undefined;
            try v.parseCLI(alloc, "foo");
            try testing.expectEqualStrings("foo", v.light);
            try testing.expectEqualStrings("foo", v.dark);
        }

        // Single whitespace
        {
            var v: Theme = undefined;
            try v.parseCLI(alloc, "  foo  ");
            try testing.expectEqualStrings("foo", v.light);
            try testing.expectEqualStrings("foo", v.dark);
        }

        // Light/dark
        {
            var v: Theme = undefined;
            try v.parseCLI(alloc, " light:foo,  dark : bar  ");
            try testing.expectEqualStrings("foo", v.light);
            try testing.expectEqualStrings("bar", v.dark);
        }

        var v: Theme = undefined;
        try testing.expectError(error.ValueRequired, v.parseCLI(alloc, null));
        try testing.expectError(error.ValueRequired, v.parseCLI(alloc, ""));
        try testing.expectError(error.InvalidValue, v.parseCLI(alloc, "light:foo"));
        try testing.expectError(error.InvalidValue, v.parseCLI(alloc, "dark:foo"));
    }
};

pub const Duration = struct {
    /// Duration in nanoseconds
    duration: u64 = 0,

    const units = [_]struct {
        name: []const u8,
        factor: u64,
    }{
        // The order is important as the first factor that matches will be the
        // default unit that is used for formatting.
        .{ .name = "y", .factor = 365 * std.time.ns_per_day },
        .{ .name = "w", .factor = std.time.ns_per_week },
        .{ .name = "d", .factor = std.time.ns_per_day },
        .{ .name = "h", .factor = std.time.ns_per_hour },
        .{ .name = "m", .factor = std.time.ns_per_min },
        .{ .name = "s", .factor = std.time.ns_per_s },
        .{ .name = "ms", .factor = std.time.ns_per_ms },
        .{ .name = "µs", .factor = std.time.ns_per_us },
        .{ .name = "us", .factor = std.time.ns_per_us },
        .{ .name = "ns", .factor = 1 },
    };

    pub fn clone(self: *const Duration, _: Allocator) error{}!Duration {
        return .{ .duration = self.duration };
    }

    pub fn equal(self: Duration, other: Duration) bool {
        return self.duration == other.duration;
    }

    pub fn round(self: Duration, to: u64) Duration {
        return .{ .duration = self.duration / to * to };
    }

    pub fn parseCLI(input: ?[]const u8) !Duration {
        var remaining = input orelse return error.ValueRequired;

        var value: ?u64 = null;
        while (remaining.len > 0) {
            // Skip over whitespace before the number
            while (remaining.len > 0 and std.ascii.isWhitespace(remaining[0])) {
                remaining = remaining[1..];
            }

            // There was whitespace at the end, that's OK
            if (remaining.len == 0) break;

            // Find the longest number
            const number = number: {
                var prev_number: ?u64 = null;
                var prev_remaining: ?[]const u8 = null;
                for (1..remaining.len + 1) |index| {
                    prev_number = std.fmt.parseUnsigned(u64, remaining[0..index], 10) catch {
                        if (prev_remaining) |prev| remaining = prev;
                        break :number prev_number;
                    };
                    prev_remaining = remaining[index..];
                }
                if (prev_remaining) |prev| remaining = prev;
                break :number prev_number;
            } orelse return error.InvalidValue;

            // A number without a unit is invalid
            if (remaining.len == 0) return error.InvalidValue;

            // Find the longest matching unit. Needs to be the longest matching
            // to distinguish 'm' from 'ms'.
            const factor = factor: {
                var prev_factor: ?u64 = null;
                var prev_index: ?usize = null;
                for (1..remaining.len + 1) |index| {
                    const next_factor = next: {
                        for (units) |unit| {
                            if (std.mem.eql(u8, unit.name, remaining[0..index])) {
                                break :next unit.factor;
                            }
                        }
                        break :next null;
                    };
                    if (next_factor) |next| {
                        prev_factor = next;
                        prev_index = index;
                    }
                }
                if (prev_index) |index| {
                    remaining = remaining[index..];
                }
                break :factor prev_factor;
            } orelse return error.InvalidValue;

            // Add our time value to the total. Avoid overflow with saturating math.
            const diff = std.math.mul(u64, number, factor) catch std.math.maxInt(u64);
            value = (value orelse 0) +| diff;
        }

        return if (value) |v| .{ .duration = v } else error.ValueRequired;
    }

    pub fn formatEntry(self: Duration, formatter: anytype) !void {
        var buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();
        try self.format("", .{}, writer);
        try formatter.formatEntry([]const u8, fbs.getWritten());
    }

    pub fn format(self: Duration, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var value = self.duration;
        var i: usize = 0;
        for (units) |unit| {
            if (value >= unit.factor) {
                if (i > 0) writer.writeAll(" ") catch unreachable;
                const remainder = value % unit.factor;
                const quotient = (value - remainder) / unit.factor;
                writer.print("{d}{s}", .{ quotient, unit.name }) catch unreachable;
                value = remainder;
                i += 1;
            }
        }
    }

    pub fn cval(self: Duration) usize {
        return @intCast(self.asMilliseconds());
    }

    /// Convenience function to convert to milliseconds since many OS and
    /// library timing functions operate on that timescale.
    pub fn asMilliseconds(self: Duration) c_uint {
        const ms: u64 = std.math.divTrunc(
            u64,
            self.duration,
            std.time.ns_per_ms,
        ) catch std.math.maxInt(c_uint);
        return std.math.cast(c_uint, ms) orelse std.math.maxInt(c_uint);
    }
};

pub const WindowPadding = struct {
    const Self = @This();

    top_left: u32 = 0,
    bottom_right: u32 = 0,

    pub fn clone(self: Self, _: Allocator) error{}!Self {
        return self;
    }

    pub fn equal(self: Self, other: Self) bool {
        return std.meta.eql(self, other);
    }

    pub fn parseCLI(input_: ?[]const u8) !WindowPadding {
        const input = input_ orelse return error.ValueRequired;
        const whitespace = " \t";

        if (std.mem.indexOf(u8, input, ",")) |idx| {
            const input_left = std.mem.trim(u8, input[0..idx], whitespace);
            const input_right = std.mem.trim(u8, input[idx + 1 ..], whitespace);
            const left = std.fmt.parseInt(u32, input_left, 10) catch
                return error.InvalidValue;
            const right = std.fmt.parseInt(u32, input_right, 10) catch
                return error.InvalidValue;
            return .{ .top_left = left, .bottom_right = right };
        } else {
            const value = std.fmt.parseInt(
                u32,
                std.mem.trim(u8, input, whitespace),
                10,
            ) catch return error.InvalidValue;
            return .{ .top_left = value, .bottom_right = value };
        }
    }

    pub fn formatEntry(self: Self, formatter: anytype) !void {
        var buf: [128]u8 = undefined;
        if (self.top_left == self.bottom_right) {
            try formatter.formatEntry(
                []const u8,
                std.fmt.bufPrint(
                    &buf,
                    "{}",
                    .{self.top_left},
                ) catch return error.OutOfMemory,
            );
        } else {
            try formatter.formatEntry(
                []const u8,
                std.fmt.bufPrint(
                    &buf,
                    "{},{}",
                    .{ self.top_left, self.bottom_right },
                ) catch return error.OutOfMemory,
            );
        }
    }

    test "parse WindowPadding" {
        const testing = std.testing;

        {
            const v = try WindowPadding.parseCLI("100");
            try testing.expectEqual(WindowPadding{
                .top_left = 100,
                .bottom_right = 100,
            }, v);
        }

        {
            const v = try WindowPadding.parseCLI("100,200");
            try testing.expectEqual(WindowPadding{
                .top_left = 100,
                .bottom_right = 200,
            }, v);
        }

        // Trim whitespace
        {
            const v = try WindowPadding.parseCLI(" 100 , 200 ");
            try testing.expectEqual(WindowPadding{
                .top_left = 100,
                .bottom_right = 200,
            }, v);
        }

        try testing.expectError(error.ValueRequired, WindowPadding.parseCLI(null));
        try testing.expectError(error.InvalidValue, WindowPadding.parseCLI(""));
        try testing.expectError(error.InvalidValue, WindowPadding.parseCLI("a"));
    }
};

test "parse duration" {
    inline for (Duration.units) |unit| {
        var buf: [16]u8 = undefined;
        const t = try std.fmt.bufPrint(&buf, "0{s}", .{unit.name});
        const d = try Duration.parseCLI(t);
        try std.testing.expectEqual(@as(u64, 0), d.duration);
    }

    inline for (Duration.units) |unit| {
        var buf: [16]u8 = undefined;
        const t = try std.fmt.bufPrint(&buf, "1{s}", .{unit.name});
        const d = try Duration.parseCLI(t);
        try std.testing.expectEqual(unit.factor, d.duration);
    }

    {
        const d = try Duration.parseCLI("100ns");
        try std.testing.expectEqual(@as(u64, 100), d.duration);
    }

    {
        const d = try Duration.parseCLI("1µs");
        try std.testing.expectEqual(@as(u64, 1000), d.duration);
    }

    {
        const d = try Duration.parseCLI("1µs1ns");
        try std.testing.expectEqual(@as(u64, 1001), d.duration);
    }

    {
        const d = try Duration.parseCLI("1µs 1ns");
        try std.testing.expectEqual(@as(u64, 1001), d.duration);
    }

    {
        const d = try Duration.parseCLI(" 1µs1ns");
        try std.testing.expectEqual(@as(u64, 1001), d.duration);
    }

    {
        const d = try Duration.parseCLI("1µs1ns ");
        try std.testing.expectEqual(@as(u64, 1001), d.duration);
    }

    {
        const d = try Duration.parseCLI("30s");
        try std.testing.expectEqual(@as(u64, 30 * std.time.ns_per_s), d.duration);
    }

    {
        const d = try Duration.parseCLI("584y 49w 23h 34m 33s 709ms 551µs 615ns");
        try std.testing.expectEqual(std.math.maxInt(u64), d.duration);
    }

    // Overflow
    {
        const d = try Duration.parseCLI("600y");
        try std.testing.expectEqual(std.math.maxInt(u64), d.duration);
    }

    // Repeated units
    {
        const d = try Duration.parseCLI("100ns100ns");
        try std.testing.expectEqual(@as(u64, 200), d.duration);
    }

    try std.testing.expectError(error.ValueRequired, Duration.parseCLI(null));
    try std.testing.expectError(error.ValueRequired, Duration.parseCLI(""));
    try std.testing.expectError(error.InvalidValue, Duration.parseCLI("1"));
    try std.testing.expectError(error.InvalidValue, Duration.parseCLI("s"));
    try std.testing.expectError(error.InvalidValue, Duration.parseCLI("1x"));
    try std.testing.expectError(error.InvalidValue, Duration.parseCLI("1 "));
}

test "test format" {
    inline for (Duration.units) |unit| {
        const d: Duration = .{ .duration = unit.factor };
        var actual_buf: [16]u8 = undefined;
        const actual = try std.fmt.bufPrint(&actual_buf, "{}", .{d});
        var expected_buf: [16]u8 = undefined;
        const expected = if (!std.mem.eql(u8, unit.name, "us"))
            try std.fmt.bufPrint(&expected_buf, "1{s}", .{unit.name})
        else
            "1µs";
        try std.testing.expectEqualSlices(u8, expected, actual);
    }
}

test "test entryFormatter" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    var p: Duration = .{ .duration = std.math.maxInt(u64) };
    try p.formatEntry(formatterpkg.entryFormatter("a", buf.writer()));
    try std.testing.expectEqualStrings("a = 584y 49w 23h 34m 33s 709ms 551µs 615ns\n", buf.items);
}

const TestIterator = struct {
    data: []const []const u8,
    i: usize = 0,

    pub fn next(self: *TestIterator) ?[]const u8 {
        if (self.i >= self.data.len) return null;
        const result = self.data[self.i];
        self.i += 1;
        return result;
    }
};

test "parse hook: invalid command" {
    const testing = std.testing;
    var cfg = try Config.default(testing.allocator);
    defer cfg.deinit();
    const alloc = cfg._arena.?.allocator();

    var it: TestIterator = .{ .data = &.{"foo"} };
    try testing.expect(try cfg.parseManuallyHook(alloc, "--command", &it));
    try testing.expect(cfg.command == null);
}

test "parse e: command only" {
    const testing = std.testing;
    var cfg = try Config.default(testing.allocator);
    defer cfg.deinit();
    const alloc = cfg._arena.?.allocator();

    var it: TestIterator = .{ .data = &.{"foo"} };
    try testing.expect(!try cfg.parseManuallyHook(alloc, "-e", &it));
    try testing.expectEqualStrings("foo", cfg.@"initial-command".?);
}

test "parse e: command and args" {
    const testing = std.testing;
    var cfg = try Config.default(testing.allocator);
    defer cfg.deinit();
    const alloc = cfg._arena.?.allocator();

    var it: TestIterator = .{ .data = &.{ "echo", "foo", "bar baz" } };
    try testing.expect(!try cfg.parseManuallyHook(alloc, "-e", &it));
    try testing.expectEqualStrings("echo foo bar baz", cfg.@"initial-command".?);
}

test "clone default" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var source = try Config.default(alloc);
    defer source.deinit();
    var dest = try source.clone(alloc);
    defer dest.deinit();

    // Should have no changes
    var it = source.changeIterator(&dest);
    try testing.expectEqual(@as(?Key, null), it.next());

    // I want to do this but this doesn't work (the API doesn't work)
    // try testing.expectEqualDeep(dest, source);
}

test "clone preserves conditional state" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var a = try Config.default(alloc);
    defer a.deinit();
    a._conditional_state.theme = .dark;
    try testing.expectEqual(.dark, a._conditional_state.theme);
    var dest = try a.clone(alloc);
    defer dest.deinit();

    // Should have no changes
    var it = a.changeIterator(&dest);
    try testing.expectEqual(@as(?Key, null), it.next());

    // Should have the same conditional state
    try testing.expectEqual(.dark, dest._conditional_state.theme);
}

test "clone can then change conditional state" {
    // This tests a particular bug sequence where:
    //   1. Load light
    //   2. Convert to dark
    //   3. Clone dark
    //   4. Convert to light
    //   5. Config is still dark (bug)
    const testing = std.testing;
    const alloc = testing.allocator;
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    // Setup our test theme
    var td = try internal_os.TempDir.init();
    defer td.deinit();
    {
        var file = try td.dir.createFile("theme_light", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_light"));
    }
    {
        var file = try td.dir.createFile("theme_dark", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_dark"));
    }
    var light_buf: [std.fs.max_path_bytes]u8 = undefined;
    const light = try td.dir.realpath("theme_light", &light_buf);
    var dark_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dark = try td.dir.realpath("theme_dark", &dark_buf);

    var cfg_light = try Config.default(alloc);
    defer cfg_light.deinit();
    var it: TestIterator = .{ .data = &.{
        try std.fmt.allocPrint(
            alloc_arena,
            "--theme=light:{s},dark:{s}",
            .{ light, dark },
        ),
    } };
    try cfg_light.loadIter(alloc, &it);
    try cfg_light.finalize();

    var cfg_dark = (try cfg_light.changeConditionalState(.{ .theme = .dark })).?;
    defer cfg_dark.deinit();

    try testing.expectEqual(Color{
        .r = 0xEE,
        .g = 0xEE,
        .b = 0xEE,
    }, cfg_dark.background);

    var cfg_clone = try cfg_dark.clone(alloc);
    defer cfg_clone.deinit();
    try testing.expectEqual(Color{
        .r = 0xEE,
        .g = 0xEE,
        .b = 0xEE,
    }, cfg_clone.background);

    var cfg_light2 = (try cfg_clone.changeConditionalState(.{ .theme = .light })).?;
    defer cfg_light2.deinit();
    try testing.expectEqual(Color{
        .r = 0xFF,
        .g = 0xFF,
        .b = 0xFF,
    }, cfg_light2.background);
}

test "clone preserves conditional set" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    var it: TestIterator = .{ .data = &.{
        "--theme=light:foo,dark:bar",
        "--window-theme=auto",
    } };
    try cfg.loadIter(alloc, &it);
    try cfg.finalize();

    var clone1 = try cfg.clone(alloc);
    defer clone1.deinit();

    try testing.expect(clone1._conditional_set.contains(.theme));
}

test "changed" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var source = try Config.default(alloc);
    defer source.deinit();
    var dest = try source.clone(alloc);
    defer dest.deinit();
    dest.@"font-thicken" = true;

    try testing.expect(source.changed(&dest, .@"font-thicken"));
    try testing.expect(!source.changed(&dest, .@"font-size"));
}

test "changeConditionalState ignores irrelevant changes" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        var it: TestIterator = .{ .data = &.{
            "--theme=foo",
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        try testing.expect(try cfg.changeConditionalState(
            .{ .theme = .dark },
        ) == null);
    }
}

test "changeConditionalState applies relevant changes" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        var it: TestIterator = .{ .data = &.{
            "--theme=light:foo,dark:bar",
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        var cfg2 = (try cfg.changeConditionalState(.{ .theme = .dark })).?;
        defer cfg2.deinit();

        try testing.expect(cfg2._conditional_set.contains(.theme));
    }
}
test "theme loading" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    // Setup our test theme
    var td = try internal_os.TempDir.init();
    defer td.deinit();
    {
        var file = try td.dir.createFile("theme", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_simple"));
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try td.dir.realpath("theme", &path_buf);

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    var it: TestIterator = .{ .data = &.{
        try std.fmt.allocPrint(alloc_arena, "--theme={s}", .{path}),
    } };
    try cfg.loadIter(alloc, &it);
    try cfg.finalize();

    try testing.expectEqual(Color{
        .r = 0x12,
        .g = 0x3A,
        .b = 0xBC,
    }, cfg.background);

    // Not a conditional theme
    try testing.expect(!cfg._conditional_set.contains(.theme));
}

test "theme loading preserves conditional state" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    // Setup our test theme
    var td = try internal_os.TempDir.init();
    defer td.deinit();
    {
        var file = try td.dir.createFile("theme", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_simple"));
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try td.dir.realpath("theme", &path_buf);

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg._conditional_state = .{ .theme = .dark };
    var it: TestIterator = .{ .data = &.{
        try std.fmt.allocPrint(alloc_arena, "--theme={s}", .{path}),
    } };
    try cfg.loadIter(alloc, &it);
    try cfg.finalize();

    try testing.expect(cfg._conditional_state.theme == .dark);
}

test "theme priority is lower than config" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    // Setup our test theme
    var td = try internal_os.TempDir.init();
    defer td.deinit();
    {
        var file = try td.dir.createFile("theme", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_simple"));
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try td.dir.realpath("theme", &path_buf);

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    var it: TestIterator = .{ .data = &.{
        "--background=#ABCDEF",
        try std.fmt.allocPrint(alloc_arena, "--theme={s}", .{path}),
    } };
    try cfg.loadIter(alloc, &it);
    try cfg.finalize();

    try testing.expectEqual(Color{
        .r = 0xAB,
        .g = 0xCD,
        .b = 0xEF,
    }, cfg.background);
}

test "theme loading correct light/dark" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    // Setup our test theme
    var td = try internal_os.TempDir.init();
    defer td.deinit();
    {
        var file = try td.dir.createFile("theme_light", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_light"));
    }
    {
        var file = try td.dir.createFile("theme_dark", .{});
        defer file.close();
        try file.writer().writeAll(@embedFile("testdata/theme_dark"));
    }
    var light_buf: [std.fs.max_path_bytes]u8 = undefined;
    const light = try td.dir.realpath("theme_light", &light_buf);
    var dark_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dark = try td.dir.realpath("theme_dark", &dark_buf);

    // Light
    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        var it: TestIterator = .{ .data = &.{
            try std.fmt.allocPrint(
                alloc_arena,
                "--theme=light:{s},dark:{s}",
                .{ light, dark },
            ),
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        try testing.expectEqual(Color{
            .r = 0xFF,
            .g = 0xFF,
            .b = 0xFF,
        }, cfg.background);
    }

    // Dark
    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        cfg._conditional_state = .{ .theme = .dark };
        var it: TestIterator = .{ .data = &.{
            try std.fmt.allocPrint(
                alloc_arena,
                "--theme=light:{s},dark:{s}",
                .{ light, dark },
            ),
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        try testing.expectEqual(Color{
            .r = 0xEE,
            .g = 0xEE,
            .b = 0xEE,
        }, cfg.background);
    }

    // Light to Dark
    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        var it: TestIterator = .{ .data = &.{
            try std.fmt.allocPrint(
                alloc_arena,
                "--theme=light:{s},dark:{s}",
                .{ light, dark },
            ),
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        var new = (try cfg.changeConditionalState(.{ .theme = .dark })).?;
        defer new.deinit();
        try testing.expectEqual(Color{
            .r = 0xEE,
            .g = 0xEE,
            .b = 0xEE,
        }, new.background);
    }
}

test "theme specifying light/dark changes window-theme from auto" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        var it: TestIterator = .{ .data = &.{
            "--theme=light:foo,dark:bar",
            "--window-theme=auto",
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        try testing.expect(cfg.@"window-theme" == .system);
    }
}

test "theme specifying light/dark sets theme usage in conditional state" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var cfg = try Config.default(alloc);
        defer cfg.deinit();
        var it: TestIterator = .{ .data = &.{
            "--theme=light:foo,dark:bar",
            "--window-theme=auto",
        } };
        try cfg.loadIter(alloc, &it);
        try cfg.finalize();

        try testing.expect(cfg.@"window-theme" == .system);
        try testing.expect(cfg._conditional_set.contains(.theme));
    }
}
