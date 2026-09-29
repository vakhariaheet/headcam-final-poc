# CreasePoint Design System

> **Design direction:** Broadcast Precision\
> A clean, modern interface for wearable cricket broadcast technology.
> CreasePoint should feel like professional broadcast equipment---not a
> generic cricket scoring app.

## 1. Product Context

CreasePoint is a wearable cricket broadcast system built around an
umpire-mounted camera. The product UI is responsible for device pairing,
device health, match/broadcast setup, stream control, recordings,
connectivity, telemetry, and settings.

**Important:** CreasePoint does **not** provide its own scoring system.
Do not design scorer-entry screens, score-editing workflows, innings
controls, batsman/bowler entry, or other manual scoring interfaces.
Where score data is required for broadcast graphics, treat it as
externally sourced/integrated data.

### Product principles

-   **Broadcast-first:** prioritize camera, stream, network, device, and
    recording information.
-   **Operational clarity:** important state must be understandable at a
    glance.
-   **Professional, not gamer-like:** avoid neon HUDs and excessive
    visual effects.
-   **Cricket-aware, not cricket-themed:** use subtle geometry and
    imagery rather than wickets, balls, and fields everywhere.
-   **Low cognitive load:** an umpire/operator should be able to start
    and monitor a broadcast quickly.
-   **Field-ready:** controls must remain readable outdoors and under
    pressure.

------------------------------------------------------------------------

## 2. Brand Idea

### Brand personality

**Precise · Modern · Reliable · Technical · Accessible ·
Broadcast-grade**

CreasePoint combines grassroots cricket with modern broadcast
infrastructure. It should feel considerably more sophisticated than
low-cost consumer hardware while remaining approachable for clubs,
academies, schools, and tournament organizers.

### Core visual concept

The CreasePoint mark combines:

-   three cricket stumps;
-   a sweeping crease/horizon;
-   a central camera/eye element.

The **sweeping arc** is the primary reusable brand motif. It may appear
subtly in loading states, charts, onboarding, device connection
progress, camera alignment, empty states, and broadcast graphics.

Do not overuse it as decoration.

------------------------------------------------------------------------

## 3. Color System

### Core palette

  Token              Hex         Primary use
  ------------------ ----------- ----------------------------------
  `navy-900`         `#071A2A`   Brand navy, dark backgrounds
  `blue-500`         `#168AF5`   Primary actions, active states
  `background`       `#F7F9FB`   Light application background
  `surface`          `#FFFFFF`   Cards, sheets, elevated surfaces
  `surface-alt`      `#EEF4F8`   Secondary/quiet surfaces
  `text-primary`     `#091A29`   Main text
  `text-secondary`   `#667685`   Supporting text
  `border`           `#DCE4EA`   Dividers and borders
  `success`          `#22A06B`   Connected, healthy, successful
  `warning`          `#F5A524`   Attention, standby, degraded
  `error`            `#E5484D`   Error, disconnected, destructive
  `live`             `#F04444`   Live broadcast state

### Color philosophy

Crease Blue is an **accent**, not a background treatment. Most
interfaces should be white/off-white/navy with blue appearing where
interaction or important information demands attention.

Reserve red primarily for:

-   `LIVE`
-   recording indicators;
-   broadcast termination;
-   critical stream failure;
-   destructive actions.

A connected device is **green**, not blue. Blue represents
interaction/active selection/streaming rather than generic success.

### Light mode

``` css
--background: #F7F9FB;
--surface: #FFFFFF;
--surface-alt: #EEF4F8;
--text-primary: #091A29;
--text-secondary: #667685;
--border: #DCE4EA;
--primary: #168AF5;
```

### Dark / broadcast mode

``` css
--background: #071A2A;
--surface: #0D2436;
--surface-alt: #122C40;
--text-primary: #FFFFFF;
--text-secondary: #AAB8C4;
--border: #20394C;
--primary: #168AF5;
```

Dark mode should not simply invert the light UI. It is especially suited
to the **live broadcast/control environment**, where video and telemetry
should dominate.

------------------------------------------------------------------------

## 4. Typography

### Primary typeface

**Inter**

Use Inter throughout the application for UI, telemetry, navigation,
headings, and supporting text.

Fallback:

``` css
font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
             "Segoe UI", sans-serif;
```

### Type scale

  Style          Size   Weight   Line height Use
  ------------ ------ -------- ------------- --------------------------------------
  Display        40px      700          48px Marketing / exceptional hero numbers
  H1             32px      700          40px Page heading
  H2             24px      600          32px Major section
  H3             18px      600          26px Card/section heading
  Body           16px      400          24px Standard copy
  Body Small     14px      400          20px Supporting UI
  Caption        12px      400          16px Metadata
  Overline       12px      500          16px Technical labels

### Technical labels

Use uppercase overlines sparingly:

`DEVICE STATUS`\
`STREAM HEALTH`\
`VIDEO`\
`NETWORK`\
`BATTERY`

Recommended:

``` css
font-size: 12px;
font-weight: 500;
letter-spacing: 0.08em;
text-transform: uppercase;
```

### Telemetry

Important values should be easy to scan.

Examples:

**82%**\
Battery

**41°C**\
Temperature

**6.8 Mbps**\
Uplink

**1080p · 30 FPS**\
Video

Use tabular numbers where available:

``` css
font-variant-numeric: tabular-nums;
```

------------------------------------------------------------------------

## 5. Spacing

Use a **4px base grid**.

Primary spacing tokens:

  Token          Value
  ------------ -------
  `space-1`        4px
  `space-2`        8px
  `space-3`       12px
  `space-4`       16px
  `space-5`       20px
  `space-6`       24px
  `space-8`       32px
  `space-10`      40px
  `space-12`      48px

Mobile screen horizontal padding: **20--24px**.

Prefer generous whitespace over dense dashboards.

------------------------------------------------------------------------

## 6. Shape Language

CreasePoint should feel engineered without becoming sterile.

### Radius

  Component                        Radius
  ---------------- ----------------------
  Small controls                      8px
  Buttons                        10--12px
  Inputs                         10--12px
  Cards                          12--16px
  Bottom sheets      20--24px top corners
  Pills/status                  Full/pill

Avoid excessive 24--32px rounding on ordinary cards.

### Borders

Default:

``` css
border: 1px solid #DCE4EA;
```

Cards should generally use either a subtle border **or** a very
restrained shadow---not both heavily.

### Shadows

Use sparingly.

``` css
box-shadow: 0 2px 8px rgba(9, 26, 41, 0.06);
```

Avoid dramatic floating/glass effects.

------------------------------------------------------------------------

## 7. Buttons

### Primary

Crease Blue background with white label.

Used for the single dominant action:

-   Start Broadcast
-   Connect Device
-   Pair UmpireHat
-   Save Changes

### Secondary

White/transparent surface with blue border or blue text.

### Ghost

No container until hover/pressed state.

### Destructive

Red. Use only for actions such as:

-   End Broadcast
-   Remove Device
-   Delete Recording

### Button hierarchy

A screen should normally contain **one obvious primary CTA**.

Minimum touch target: **44×44px**.

------------------------------------------------------------------------

## 8. Status Language

Status must never rely on color alone.

  State                 Color      Example
  --------------------- ---------- -------------
  Connected / Healthy   Green      ● Connected
  Streaming             Blue       ● Streaming
  Standby               Amber      ● Standby
  Offline               Red/Gray   ● Offline
  Live                  Red        ● LIVE

For critical broadcast states, combine:

**icon + color + label**

rather than displaying only a colored dot.

------------------------------------------------------------------------

## 9. Iconography

Use clean, geometric line icons.

Recommended characteristics:

-   1.75--2px stroke;
-   rounded joins where appropriate;
-   minimal detail;
-   consistent optical size;
-   20--24px standard size.

Typical icons:

Home · Live · Devices · Recordings · Network · Bluetooth · Battery ·
Temperature · Camera · Settings · Alerts

Avoid illustrative or skeuomorphic icons in functional UI.

------------------------------------------------------------------------

## 10. Navigation

Recommended primary mobile navigation:

**Home · Live · Devices · Recordings · Settings**

`Live` should become visually prominent while a broadcast is active.

Do **not** include a Scoring tab.

Analytics should only exist where there is meaningful device/broadcast
information to analyze---for example stream stability, recording
history, device temperature, connectivity, or usage---not as a cricket
scoring analytics substitute.

------------------------------------------------------------------------

## 11. Home Screen

The home screen answers:

1.  Is my UmpireHat ready?
2.  What is its health?
3.  Can I start broadcasting?
4.  What did I record recently?

Suggested hierarchy:

``` text
Header / CreasePoint

Greeting / contextual message

UmpireHat Device Card
├── Connection
├── Battery
├── Temperature
├── Signal
└── Start Broadcast

Recent Recordings

Readiness / Setup Card

Bottom Navigation
```

Do not make the home screen a cricket scoreboard.

------------------------------------------------------------------------

## 12. Device Card

A device card should expose only actionable health information.

Example:

``` text
UmpireHat 01                         >
● Connected

82%                 41°C            Excellent
Battery             Temperature     Signal

[ Start Broadcast ]
```

Optional telemetry when available:

-   battery;
-   SoC temperature;
-   signal/network quality;
-   camera status;
-   storage remaining;
-   firmware;
-   stream readiness.

Use progressive disclosure for advanced diagnostics.

------------------------------------------------------------------------

## 13. Live Broadcast UI

The live screen is the most important operational screen.

Dark mode is preferred.

### Hierarchy

``` text
LIVE                         01:42:18

Streaming from UmpireHat 01

┌────────────────────────────┐
│                            │
│       CAMERA PREVIEW       │
│                       LIVE │
│                            │
│ 1080p · 30 FPS    6.8 Mbps │
└────────────────────────────┘

Battery        Temperature       Signal
82%            41°C              Excellent

[ End Broadcast ]

Device | Network | Settings
```

### Priority order

1.  Is the stream live?
2.  What is the operator seeing?
3.  Is video healthy?
4.  Is network healthy?
5.  Is hardware healthy?
6.  How do I safely end/manage the stream?

Avoid cluttering the live view with nonessential cricket data.

If external scoring integration is enabled, scoreboard-overlay status
may be shown as a **broadcast integration state**, not as editable
scoring controls.

Example:

``` text
Score Overlay
● Synced
Source: External integration
```

------------------------------------------------------------------------

## 14. Recordings

Recordings should be media-first.

Each recording card may contain:

-   thumbnail;
-   title;
-   date/time;
-   duration;
-   resolution;
-   upload/cloud state.

Example:

``` text
[ thumbnail ]  12:34

Match Practice
14 Sep 2026 · 1080p
```

Use large thumbnails rather than dense table layouts on mobile.

------------------------------------------------------------------------

## 15. Device Setup & Pairing

Setup should feel nearly effortless.

Recommended flow:

``` text
Find UmpireHat
      ↓
BLE Pairing
      ↓
Wi-Fi / Connectivity
      ↓
Camera Test
      ↓
Broadcast Integration
      ↓
Ready
```

Show progress clearly and keep advanced networking behind optional
controls.

Target experience: **under 60 seconds for a previously configured
device**.

------------------------------------------------------------------------

## 16. External Score / Match Integration

CreasePoint does not score matches.

Any CricHeroes or equivalent integration should be framed as an external
data source used by the broadcast pipeline.

UI terminology:

-   Connect Match
-   Match ID
-   Score Overlay
-   Data Source
-   Overlay Synced
-   Last Updated
-   Reconnect

Avoid:

-   Add Run
-   Add Wicket
-   Select Bowler
-   New Batsman
-   End Over
-   Undo Ball

Those belong to scoring products, not CreasePoint.

------------------------------------------------------------------------

## 17. Brand Motif: The Crease Arc

The logo's curved horizon is the signature graphical device.

Appropriate applications:

-   connection animation;
-   onboarding;
-   loading indicator;
-   camera alignment;
-   empty-state illustration;
-   subtle chart shape;
-   broadcast transition;
-   section divider;
-   marketing imagery mask.

Keep it restrained. A normal settings form does not need an arc behind
it.

------------------------------------------------------------------------

## 18. Imagery

Photography should communicate **perspective and broadcast access**.

Prefer:

-   umpire POV;
-   camera mounted on hat;
-   pitch viewed from behind the stumps;
-   authentic grassroots grounds;
-   broadcast equipment details;
-   match preparation;
-   field-level perspectives.

Avoid:

-   generic stock cricket celebrations;
-   oversaturated stadium imagery;
-   fake futuristic HUD overlays;
-   excessive professional international-stadium imagery if the product
    targets grassroots cricket.

Image treatment should be natural, slightly cinematic, and credible.

------------------------------------------------------------------------

## 19. Motion

Motion should reinforce state.

Recommended durations:

-   micro-interaction: `120–180ms`
-   component transition: `180–240ms`
-   sheet/page transition: `240–320ms`

Useful animation:

-   BLE searching;
-   device connected;
-   stream starting;
-   recording pulse;
-   live transition;
-   upload progress;
-   network degradation/recovery.

The `LIVE` indicator may use a subtle pulse. Avoid constant motion
elsewhere.

------------------------------------------------------------------------

## 20. Accessibility & Field Use

The application will be used outdoors, so visual accessibility is
operationally important.

Requirements:

-   maintain WCAG-friendly text contrast;
-   minimum 16px for important operational text;
-   44px minimum touch targets;
-   do not encode state using color alone;
-   keep primary actions visually obvious;
-   avoid low-contrast gray-on-gray interfaces;
-   keep live telemetry readable at a glance;
-   provide clear confirmation before ending a broadcast.

------------------------------------------------------------------------

## 21. Design Anti-Patterns

Do **not** turn CreasePoint into:

-   a generic cricket scorer;
-   a fantasy-cricket interface;
-   a neon esports dashboard;
-   a sci-fi HUD;
-   a glassmorphism showcase;
-   a gradient-heavy SaaS template;
-   a dashboard with dozens of metrics;
-   a UI covered in cricket-ball/stump decorations.

Avoid excessive:

-   gradients;
-   glowing borders;
-   glass panels;
-   shadows;
-   rounded cards;
-   decorative charts;
-   blue surfaces;
-   animation.

The technology itself is interesting enough. The interface should
communicate confidence and clarity.

------------------------------------------------------------------------

## 22. Design Summary

**CreasePoint = Broadcast Precision.**

The system should visually feel like a compact professional broadcast
console built for grassroots cricket.

The visual hierarchy is:

**Navy + White → structure**\
**Crease Blue → interaction / active technology**\
**Green → healthy**\
**Amber → attention**\
**Red → live / critical / destructive**

Typography is **Inter**, geometry is clean and restrained, cards use
modest rounding, telemetry is highly legible, and the CreasePoint arc
provides the recognizable brand signature.

Above all, every product screen should answer:

> **What does the operator need to know or do right now to capture and
> broadcast reliably?**
