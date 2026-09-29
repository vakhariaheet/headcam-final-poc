# **UmpireHat Master Spec: End-to-End System Architecture & Technical Specifications**

**Comprehensive Architectural Blueprint, Edge Hardware Engineering, Flutter Companion Gateway, Cloud Compositing Pipeline, and Relational Database Schema for Live Cricket Broadcasting**

## **1\. Executive Summary & System Overview**

### **1.1 Problem Statement & Industry Context**

Grassroots cricket streaming across regional tournaments, club championships, school leagues, and training academies has historically been constrained by boundary-mounted camera infrastructure. Standard commercial solutions—such as CricHeroes Capture systems or 4K Pan-Tilt-Zoom (PTZ) optical rigs—command unit costs between ₹45,000 and ₹70,000+. Beyond prohibitive capital costs, boundary camera setups introduce critical structural and operational liabilities:

> * **Boundary Line-of-Sight Occlusions:** Positioned 60 to 75 meters away from the pitch, boundary cameras frequently suffer from complete visual obstruction caused by deep outfielders, umpires walking across the field, boundary riders, or spectators.  
> * **Ball Strike Vulnerability:** Pitch-level or low-tripod setups facing down the ground are exposed to high-velocity straight drives (120–150 km/h), often resulting in lens destruction or equipment damage in the absence of heavy protective cages.  
> * **Severe Thermal Throttling:** Ground-level hardware stationed on open fields under direct summer sunlight (ambient temperatures ranging from 40°C to 44°C) routinely experiences thermal shutdown, battery swelling, and sensor noise amplification.  
> * **High Operational Overhead:** Operating a boundary rig mandates a dedicated technician or camera operator to adjust framing, manage umbilical power cords, calibrate HDMI capture interfaces, and monitor uplink health.

### **1.2 System Vision & Value Proposition**

The UmpireHat System replaces boundary rigs by embedding an ultra-lightweight, high-efficiency vision processing node directly onto the brim of an official umpire hat. By positioning the optical sensor directly behind the stumps at bowler's or striker's end, the system captures an immersive, first-person point of view (POV) aligned with the umpire's natural line of sight. This perspective delivers optimal visual clarity for adjudicating LBW trajectory, bat-pad edges, bowler front-foot delivery strides, and stump-to-stump movement.

The architecture shifts resource-intensive operations to dedicated domains: video capture and hardware encoding occur at the edge on an ultra-low-power SoC, broadcast graphics rendering and alpha composition run on headless cloud workers, and device provisioning and telemetry monitoring are handled via an intuitive Flutter companion app. Consequently, the total Bill of Materials (BOM) is constrained to under ₹4,800, enabling zero-crew broadcast automation with synchronized CricHeroes scoreboards and multi-platform simulcasting.

### **1.3 High-Level Architectural Comparison**

| System Dimension | Traditional Boundary Rigs (PTZ / Capture Kits) | UmpireHat Embedded POV Broadcast System&nbsp;&nbsp; |
| :---- | :---- | :---- |
| **Camera Perspective** | Distanced boundary view (60–75m from pitch), obstructed by outfielders and boundary traffic. | Direct Stumps POV; unobstructed optical sightline for LBWs, snicks, and bowler release stride. |
| **Unit Hardware Cost** | ₹45,000 to ₹70,000+ per unit. | \~₹4,750 per unit (BOM cost). |
| **Operational Crew** | Requires 1–2 dedicated operators for tracking, panning, cabling, and broadcast oversight. | Zero crew. Worn natively by the match umpire; automated cloud streaming triggered via mobile. |
| **Equipment Safety** | High risk of catastrophic destruction from straight drives; demands heavy metal shields. | Safely integrated onto the match official's headgear away from low-pitch impacts. |
| **Setup Time** | 20–30 minutes (cabling, tripod leveling, capture card testing, wireless link pairing). | \< 60 seconds (One-tap BLE pairing and CricHeroes Match ID injection). |
| **Graphics Integration** | Requires on-site OBS laptop or manual scoreboard input software. | Automated cloud worker overlay rendering with dynamic CricHeroes regex parsing. |

## **2\. End-to-End System Architecture & Dataflow**

### **2.1 Macro Architecture Walkthrough**

The UmpireHat broadcast ecosystem decouples video capture, overlay synthesis, and stream distribution into three independent functional tiers:

> 1. **Edge Vision Node (The Hat):** A lightweight embedded subsystem mounted to the umpire's hat brim. It ingests optical data through a 3MP CMOS sensor, executes on-chip image signal processing (ISP), downsamples the frame to 1080p at 30 fps, and compresses the stream using hardware-accelerated H.265 (HEVC) Constant Bitrate (CBR) encoding at 2.2 Mbps. Concurrently, an onboard analog microphone captures pitch audio, routes it through acoustic foam, and applies a firmware-level high-pass filter before encoding it into AAC at 128 kbps. The multiplexed transport stream is encapsulated into RTSP and transmitted over a 5 GHz Wi-Fi link tethered to the umpire's smartphone hotspot.  
> 2. **Mobile Control Gateway (Flutter Companion Application):** Runs locally on the umpire's iOS or Android device. The application performs zero-configuration BLE scanning, pushes encrypted cellular hotspot credentials into the edge node's non-volatile storage, performs automated URL parsing on pasted CricHeroes match links, runs a 3-second pre-flight diagnostic, and coordinates stream initialization with the cloud orchestrator.  
> 3. **Cloud Ingestion, Compositing & Distribution Worker:** Hosted on cloud GPU/compute instances running Docker. The worker orchestrates MediaMTX for low-latency RTSP ingestion, spins up a headless Chromium container via Puppeteer to render the transparent CricHeroes HTML5 scoreboard overlay at 1920×1080@30fps, alpha-composites the graphics onto the raw video using hardware-accelerated FFmpeg filtergraphs, and fans out the final feed over RTMPS simultaneously to YouTube Live and Facebook Live.

### **2.2 Transport Pipelines & Protocols**

| Stage | Source → Target | Protocol / Format | Key Parameters & Throughput&nbsp;&nbsp; |
| :---- | :---- | :---- | :---- |
| **Provisioning & Telemetry** | Flutter App ↔ Hat Node | BLE GATT (Custom Services) | Service 0xFFE0, Chars 0xFFE1/0xFFE2; 100 ms telemetry ticks. |
| **Edge Uplink** | Hat Node → Cloud MediaMTX | RTSP over TCP / UDP | 1080p30 H.265 (HEVC) @ 2.2 Mbps \+ AAC 128 kbps. 5 GHz Wi-Fi tether. |
| **Overlay Pipeline** | Puppeteer → Named Pipe | Raw RGBA Pixel Stream | 1920×1080 @ 30 fps uncompressed RGBA into Linux FIFO pipe. |
| **Broadcast Egress** | Cloud FFmpeg → YouTube / Meta | RTMPS / RTMP (Tee Muxer) | 1080p30 H.264 Baseline/High @ 2.5 Mbps, Keyframe Interval: 2.0s (g=60). |

## **3\. Bill of Materials & Hardware Engineering**

### **3.1 Itemized Hardware Bill of Materials (BOM)**

The edge node is engineered to satisfy three uncompromising hardware constraints: payload weight under 55 grams on the brim, sustained power draw below 2.0 Watts, and operational stability up to 45°C ambient temperature under intense direct sun.

| Subsystem / Component | Part Selection | Technical Justification & Operating Characteristics | Cost (INR)&nbsp;&nbsp; |
| ----- | :---- | :---- | ----- |
| **Vision Processor / Core SoC** | Realtek AmebaPro2 (AMB82-Mini) | Dedicated multi-stream H.265/H.264 VPU, integrated dual-band Wi-Fi (2.4/5GHz 802.11a/b/g/n), BLE 5.1, ultra-low power consumption (\<1.8W full encode load), onboard audio codec. | ₹3,200 |
| **CMOS Image Sensor** | SmartSens SC3336 (Waveshare Type-B) | Native 3MP resolution (2304×1296) downsampled on-chip to 1080p30 for superior sharpness, high dynamic range (HDR) handling under harsh midday sun, MIPI-CSI2 interface. | ₹1,100 |
| **Acoustic Assembly** | Onboard Analog Mic \+ Open-Cell Foam | Brim underside pinhole orientation; high-density open-cell polyurethane foam for acoustic wind buffeting isolation (\>15 dB suppression across low-frequency gust spectra). | ₹50 |
| **Enclosure & Mechanics** | UV-Resistant White PETG Enclosure | Reflective solar white casing with integrated brim retention clip, vertical passive convection chimneys, weight budget strictly \<55 grams. | ₹250 |
| **Power Interconnect** | 1.2m Braided Right-Angle Type-C Cable | High-flexibility braided cable routing unobtrusively down the collar to an umpire pocket-carried power bank (5,000–10,000 mAh providing 8–14 hours of continuous broadcast). | ₹150 |
| **Total Per-Unit Bill of Materials (BOM):** |  |  | **\~₹4,750** |

### **3.2 Thermal & Mechanical Architecture**

Thermal throttling is the most frequent cause of embedded edge video failures in cricket environments. The UmpireHat enclosure addresses this via multi-path passive heat dissipation:

> * **Solar Radiation Rejection:** The enclosure is fabricated from UV-stabilized white PETG filament, reflecting over 90% of direct incident solar energy.  
> * **Vertical Convection Chimneys:** Dual internal air channels flank the AMB82-Mini SoC, creating a passive draft effect where warm air naturally vents through top louvers while cooler ambient air enters from shielded bottom intake vents.  
> * **Center of Gravity Alignment:** The optical axis sits 12mm above the hat brim, while the logic board and heatsink are positioned flush against the crown curve to prevent forward neck fatigue.

## **4\. Hotspot Profiling & BLE Provisioning Workflow**

### **4.1 The Sandboxing Challenge**

Both Apple iOS and Google Android strictly sandbox cellular hotspot configurations. Third-party applications cannot query the operating system to retrieve the active personal hotspot SSID or passphrase. Requiring an umpire to manually enter Wi-Fi credentials prior to every match is impractical and error-prone in field settings.

### **4.2 One-Time Hotspot Profiling Protocol**

To eliminate pre-match friction, UmpireHat implements a decoupled credential injection flow:

> 1. **Initial User Onboarding:** During initial app onboarding, the umpire manually inputs their smartphone's Personal Hotspot SSID and Passphrase once.  
> 2. **Encrypted Keystore Storage:** Credentials are encrypted with AES-256-GCM and stored in the smartphone's hardware-backed secure storage (iOS Keychain / Android Keystore) via the flutter\_secure\_storage library.  
> 3. **Proximity Handshake on Match Day:** When the hat powers on, its BLE peripheral advertises Service UUID 0xFFE0. The Flutter companion application automatically connects within 500 ms and injects the encrypted provisioning payload over Characteristic 0xFFE1.

### **4.3 BLE GATT Provisioning Payload Schema**

The companion application dispatches a structured JSON payload to the AMB82-Mini provisioning characteristic:

{  
&nbsp;&nbsp;"cmd": "SET\_STA",  
&nbsp;&nbsp;"ssid": "Heet\_iPhone\_5G",  
&nbsp;&nbsp;"pass": "MatchBroadcast2026",  
&nbsp;&nbsp;"band": "5GHz",  
&nbsp;&nbsp;"session\_token": "usr\_98a7c2b4e1"  
}

Upon parsing this payload, the Realtek AmebaPro2 writes the credentials into on-chip Non-Volatile Flash (NVS), initiates a connection to the phone's 5 GHz hotspot interface, obtains a local DHCP lease, and writes its operational status and assigned IP address to Characteristic 0xFFE2.

## **5\. CricHeroes Integration & Cloud Compositing Pipeline**

### **5.1 Regex URL Parsing Subsystem**

CricHeroes does not maintain a public REST/GraphQL API for third-party broadcast scoring synchronization. The Flutter app bypasses this limitation by ingesting any standard public match URL shared by the scorer and extracting the numerical match token via an optimized regular expression:

Regex Pattern: (?:cricheroes\\.com\\/match\\/(?:scorecard\\/)?)(\\d+)

Input Link:   https://cricheroes.com/match/scorecard/9482014/final-super-strikers-vs-royal-lions  
Extracted ID: 9482014  
Render URL:   https://cricheroes.com/overlay/v2/scoreboard?match\_id=9482014\&theme=standard

### **5.2 Headless Chromium DOM Rendering**

To ensure responsive visual score updates without maintaining bespoke SVG engines, a cloud worker spins up a Puppeteer headless Chromium instance configured with a transparent background:

> * **Viewport Configuration:** Standardized to 1920×1080 resolution with a device scale factor of 1.0.  
> * **Hardware Acceleration:** Launched with \--use-gl=angle and \--enable-accelerated-2d-canvas for rapid DOM redraws.  
> * **Screencast Capture:** Captures rendered DOM frames directly from the compositor at 30 fps and pipes the uncompressed raw RGBA stream into a Unix FIFO pipe (/tmp/overlay\_pipe).

### **5.3 Hardware-Accelerated FFmpeg Alpha Compositing & Simulcast**

The incoming edge RTSP stream and the RGBA overlay buffer are blended using FFmpeg's filter\_complex overlay engine. The composited video is re-encoded once via libx264 and piped through FFmpeg's tee multiplexer to simulcast directly to YouTube and Facebook Live:

ffmpeg \-re \-i rtsp://edge-node-mumbai/stream/live\_session \\  
&nbsp;&nbsp;\-f rawvideo \-pix\_fmt rgba \-s 1920x1080 \-r 30 \-i /tmp/overlay\_pipe \\  
&nbsp;&nbsp;\-filter\_complex "\[0:v\]\[1:v\]overlay=0:0:format=auto\[outv\]" \\  
&nbsp;&nbsp;\-map "\[outv\]" \-map 0:a \\  
&nbsp;&nbsp;\-c:v libx264 \-preset veryfast \-b:v 2500k \-maxrate 2800k \-bufsize 5600k \-g 60 \\  
&nbsp;&nbsp;\-c:a aac \-b:a 128k \\  
&nbsp;&nbsp;\-f tee "\[f=flv\]rtmp://a.rtmp.youtube.com/live2/${YT\_KEY}|\[f=flv\]rtmps://live-api-s.facebook.com:443/rtmp/${FB\_KEY}"

## **6\. Flutter Mobile Application Blueprint**

### **6.1 Mobile Application Architecture**

The companion mobile app is architected with Flutter 3.x using the Riverpod state management framework, isolating hardware I/O, cloud session synchronization, and local UI state.

### **6.2 Screen Flows, Core Responsibilities & Edge Cases**

| Screen & Component | Core Features & User Interactions | Edge Cases & Fault Mitigation&nbsp;&nbsp; |
| :---- | :---- | :---- |
| **Screen 1: Authentication & Channels** | Sign in with Google (YouTube Data API v3 live scope), Meta OAuth (Facebook Pages API), and custom RTMP ingest endpoints. | Handles YouTube 24-hour live streaming activation lockout; automated background refresh of expiring OAuth tokens. |
| **Screen 2: Device Discovery & BLE** | Radar visual scanning for UmpireHat\_XXXX advertisements; live RSSI readout; single-tap pairing handshake. | Triggers native Bluetooth system prompt if adapter is disabled; enforces an 8-second handshake timeout with auto-retry. |
| **Screen 3: Hotspot & Network Provisioning** | Allows selection between One-Time Hotspot Profiling preset and venue Wi-Fi; writes credentials directly over BLE. | Detects unbroadcasted phone hotspot states; alerts user immediately if the AMB82-Mini fails DHCP handshake. |
| **Screen 4: Match Setup & Overlay** | CricHeroes URL input field with real-time regex parsing; displays confirmed Team A vs. Team B match badge; platform destination toggles. | Validates URL structure; handles unpublished or inactive matches by rendering a neutral placeholder card. |
| **Screen 5: 3-Second Pre-Flight Check** | 3-second low-resolution RTSP preview; horizon level horizon check (\<10° tilt via hat accelerometer); audio VU meter; 4G/5G uplink speed audit. | Hard-blocks broadcast start if camera pitch/roll exceeds safety tolerance or cellular uplink bandwidth is under 2.0 Mbps. |
| **Screen 6: Live Broadcast Console** | Live match duration timer; power bank battery %; SoC core temperature (°C); outbound bitrate (kbps); one-touch Emergency Kill Switch. | RTSP disconnection switches cloud egress to a branded "Technical Difficulties" slate rather than dropping stream connections. |
| **Screen 7: Dynamic Island & Live Activity** | Lock-screen and Dynamic Island heads-up display showing live broadcast indicator, real-time score, hat battery, and stop toggle. | Enables the umpire to verify continuous broadcast integrity without unlocking the phone or breaking match concentration. |

## **7\. Production Database Architecture (PostgreSQL 16 & TimescaleDB)**

### **7.1 Schema Design Strategy**

The data tier leverages PostgreSQL 16 for strongly-typed relational entities (multi-tenant organizations, hardware provisioning, OAuth credentials, broadcast destinations) and the TimescaleDB extension for high-frequency time-series telemetry logs (bitrate, temperature, frame drops).

### **7.2 Complete Production DDL Specification**

\-- Custom Domain Enumerations  
CREATE TYPE user\_role\_enum AS ENUM ('SUPERADMIN', 'TOURNAMENT\_ADMIN', 'BROADCASTER', 'UMPIRE');  
CREATE TYPE hardware\_model\_enum AS ENUM ('AMB82\_MINI\_V1', 'ESP32\_P4\_DEV', 'AMB82\_PRO\_V2');  
CREATE TYPE device\_status\_enum AS ENUM ('UNPROVISIONED', 'PAIRING', 'READY', 'STREAMING', 'MAINTENANCE');  
CREATE TYPE streaming\_platform\_enum AS ENUM ('YOUTUBE', 'FACEBOOK', 'CUSTOM\_RTMP');  
CREATE TYPE stream\_status\_enum AS ENUM ('IDLE', 'INITIALIZING', 'LIVE', 'RECONNECTING', 'TERMINATED', 'FAILED');

\-- 1\. Multi-Tenant Organizations & User Directory  
CREATE TABLE organizations (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;name VARCHAR(128) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;slug VARCHAR(64) UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;billing\_tier VARCHAR(32) DEFAULT 'STANDARD',  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP  
);

CREATE TABLE users (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;organization\_id UUID REFERENCES organizations(id) ON DELETE SET NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;email VARCHAR(255) UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;first\_name VARCHAR(64) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;last\_name VARCHAR(64),  
&nbsp;&nbsp;&nbsp;&nbsp;role user\_role\_enum DEFAULT 'UMPIRE',  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP  
);

\-- 2\. Hardware Fleet Management & Encrypted Presets  
CREATE TABLE devices (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;serial\_number VARCHAR(64) UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;mac\_address MACADDR UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;ble\_uuid UUID UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;hardware\_model hardware\_model\_enum NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;firmware\_version VARCHAR(32) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;current\_status device\_status\_enum DEFAULT 'UNPROVISIONED',  
&nbsp;&nbsp;&nbsp;&nbsp;battery\_health\_pct SMALLINT CHECK (battery\_health\_pct BETWEEN 0 AND 100),  
&nbsp;&nbsp;&nbsp;&nbsp;assigned\_user\_id UUID REFERENCES users(id) ON DELETE SET NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP  
);

CREATE TABLE hotspot\_profiles (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;user\_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,  
&nbsp;&nbsp;&nbsp;&nbsp;device\_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,  
&nbsp;&nbsp;&nbsp;&nbsp;ssid VARCHAR(64) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;encrypted\_passphrase TEXT NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;passphrase\_iv VARCHAR(32) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;passphrase\_tag VARCHAR(32) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;frequency\_band VARCHAR(8) DEFAULT '5GHz',  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP,  
&nbsp;&nbsp;&nbsp;&nbsp;UNIQUE(user\_id, ssid)  
);

\-- 3\. Third-Party OAuth Integrations & Broadcast Sinks  
CREATE TABLE oauth\_integrations (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;user\_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,  
&nbsp;&nbsp;&nbsp;&nbsp;platform streaming\_platform\_enum NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;platform\_account\_id VARCHAR(128) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;account\_name VARCHAR(128) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;encrypted\_access\_token TEXT NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;encrypted\_refresh\_token TEXT,  
&nbsp;&nbsp;&nbsp;&nbsp;token\_expires\_at TIMESTAMPTZ NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;is\_valid BOOLEAN DEFAULT TRUE,  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP,  
&nbsp;&nbsp;&nbsp;&nbsp;UNIQUE(user\_id, platform, platform\_account\_id)  
);

CREATE TABLE broadcast\_destinations (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;integration\_id UUID NOT NULL REFERENCES oauth\_integrations(id) ON DELETE CASCADE,  
&nbsp;&nbsp;&nbsp;&nbsp;destination\_name VARCHAR(128) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;platform streaming\_platform\_enum NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;target\_id VARCHAR(128) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;custom\_rtmp\_url VARCHAR(255),  
&nbsp;&nbsp;&nbsp;&nbsp;encrypted\_custom\_stream\_key TEXT,  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP  
);

\-- 4\. Match Records & CricHeroes Entity Links  
CREATE TABLE matches (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;cricheroes\_match\_id VARCHAR(32) UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;raw\_input\_url TEXT NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;tournament\_name VARCHAR(128),  
&nbsp;&nbsp;&nbsp;&nbsp;team\_a\_name VARCHAR(64) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;team\_b\_name VARCHAR(64) NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;overlay\_web\_url TEXT NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP  
);

\-- 5\. Broadcast Sessions & Simulcast Routing Table  
CREATE TABLE stream\_sessions (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;session\_token VARCHAR(64) UNIQUE NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;device\_id UUID NOT NULL REFERENCES devices(id),  
&nbsp;&nbsp;&nbsp;&nbsp;user\_id UUID NOT NULL REFERENCES users(id),  
&nbsp;&nbsp;&nbsp;&nbsp;match\_id UUID NOT NULL REFERENCES matches(id),  
&nbsp;&nbsp;&nbsp;&nbsp;status stream\_status\_enum DEFAULT 'INITIALIZING',  
&nbsp;&nbsp;&nbsp;&nbsp;hat\_ingress\_rtsp\_url TEXT,  
&nbsp;&nbsp;&nbsp;&nbsp;initialized\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP,  
&nbsp;&nbsp;&nbsp;&nbsp;live\_started\_at TIMESTAMPTZ,  
&nbsp;&nbsp;&nbsp;&nbsp;ended\_at TIMESTAMPTZ,  
&nbsp;&nbsp;&nbsp;&nbsp;total\_reconnections INTEGER DEFAULT 0  
);

CREATE TABLE session\_destinations (  
&nbsp;&nbsp;&nbsp;&nbsp;id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
&nbsp;&nbsp;&nbsp;&nbsp;session\_id UUID NOT NULL REFERENCES stream\_sessions(id) ON DELETE CASCADE,  
&nbsp;&nbsp;&nbsp;&nbsp;destination\_id UUID NOT NULL REFERENCES broadcast\_destinations(id),  
&nbsp;&nbsp;&nbsp;&nbsp;platform streaming\_platform\_enum NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;platform\_broadcast\_id VARCHAR(128),  
&nbsp;&nbsp;&nbsp;&nbsp;stream\_key TEXT NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;ingest\_endpoint TEXT NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;egress\_status stream\_status\_enum DEFAULT 'INITIALIZING',  
&nbsp;&nbsp;&nbsp;&nbsp;created\_at TIMESTAMPTZ DEFAULT CURRENT\_TIMESTAMP  
);

\-- 6\. TimescaleDB Telemetry Metric Stream (Hypertable)  
CREATE TABLE telemetry\_samples (  
&nbsp;&nbsp;&nbsp;&nbsp;recorded\_at TIMESTAMPTZ NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;session\_id UUID NOT NULL,  
&nbsp;&nbsp;&nbsp;&nbsp;battery\_level\_pct SMALLINT,  
&nbsp;&nbsp;&nbsp;&nbsp;soc\_temperature\_c NUMERIC(4,1),  
&nbsp;&nbsp;&nbsp;&nbsp;outbound\_bitrate\_kbps INTEGER,  
&nbsp;&nbsp;&nbsp;&nbsp;fps NUMERIC(4,1),  
&nbsp;&nbsp;&nbsp;&nbsp;packet\_loss\_pct NUMERIC(4,2)  
);

\-- Indexing Strategy  
CREATE INDEX idx\_telemetry\_time ON telemetry\_samples USING BRIN (recorded\_at);  
CREATE INDEX idx\_telemetry\_session ON telemetry\_samples (session\_id, recorded\_at DESC);

## **8\. Resiliency Protocols, Failovers & Automated Recovery**

### **8.1 Accidental Cable Disconnection & Fast Re-Attach**

If an umpire accidentally snags or dislodges the USB-C power cable during play, the AMB82-Mini powers down immediately. The system recovers autonomously:

> * **Sub-3.2 Second Cold Boot:** Upon cable reinsertion, the FreeRTOS bootloader initializes the core SoC, reads cached hotspot credentials and the existing session token from flash memory, and re-establishes the 5 GHz Wi-Fi association.  
> * **Cloud Worker Ingest Holding Loop:** The cloud MediaMTX and FFmpeg pipeline maintains the egress RTMP socket connection to YouTube and Facebook Live for up to 30 seconds, looping a branded freeze-frame with a "Play Continues — Stream Reconnecting" overlay rather than terminating the live broadcast.

### **8.2 Thermal Runaway Under Subcontinental Climates**

Open cricket grounds in regions like Ahmedabad or Delhi routinely reach 42°C to 44°C ambient temperatures during afternoon matches. The firmware operates a staged thermal management routine:

> * **Passive Heat Exhaust:** The white PETG shell deflects \>90% of solar irradiance, while convective internal airflow keeps internal junction delta under \+18°C above ambient under normal wind movement.  
> * **Telemetry Warning Threshold (70°C):** The SoC emits a warning state via BLE to the Flutter companion app, prompting a notification banner on the umpire's phone.  
> * **Critical Threshold (75°C):** The AMB82-Mini firmware locks the hardware video encoder strictly to 1080p30 Constant Bitrate (CBR) and throttles background system tasks. This guarantees continuous frame delivery without encoder stall or dropped keyframes.

### **8.3 Mid-Innings OAuth Token Expiration**

Cricket matches regularly span 3.5 to 7 hours across T20 and One-Day formats, whereas Google OAuth access tokens expire every 60 minutes. A background orchestration daemon in the cloud worker polls all active broadcast sessions every 10 minutes. When a token validity window drops below 15 minutes, the worker silently negotiates a new access token using the encrypted refresh token, keeping the active RTMP push session uninterrupted.

### **8.4 Uplink Degradation & Adaptive Rate Control**

When an umpire moves into a partial cellular shadow or carrier tower congestion occurs, RTCP packet loss reports trigger the AMB82-Mini rate control algorithm to step down the encoding bitrate dynamically (from 2,200 kbps to 1,400 kbps) while preserving the 30 fps cadence. The cloud FFmpeg worker absorbs any jitter through a 3,000 ms ring buffer before muxing into the egress stream.

## **9\. Implementation Roadmap & Milestones**

| Sprint & Phase | Primary Engineering Deliverables | Exit Criteria & Target Validation&nbsp;&nbsp; |
| :---- | :---- | :---- |
| **Sprint 1: Edge Firmware & RTSP Pipeline** | AmebaPro2 SDK flashing on AMB82-Mini; SC3336 ISP calibration for 1080p30 H.265; onboard AAC audio muxing with acoustic wind filter; BLE GATT provisioning service (UUID 0xFFE0). | Stable 2.2 Mbps RTSP egress over 5 GHz hotspot; \<55g assembly; power consumption strictly \<1.8W. |
| **Sprint 2: Flutter Companion Gateway** | Cross-platform Bluetooth Low Energy handshake via flutter\_blue\_plus; One-Time Hotspot Profiling screen with flutter\_secure\_storage; CricHeroes regex match URL parser. | Automated device discovery and Wi-Fi credential provisioning completed in \<2 seconds from hat boot. |
| **Sprint 3: Cloud Compositor & Ingestion** | Containerized MediaMTX deployment; Puppeteer headless Chromium container rendering transparent CricHeroes overlay; FFmpeg filter\_complex alpha compositing and tee multiplexer. | Glass-to-glass latency \<2.5s; 1080p30 broadcast with real-time score updates matching CricHeroes live state. |
| **Sprint 4: Broadcast APIs & Field Trials** | YouTube Data API v3 and Meta Live Video API integrations; Live Activity / Dynamic Island background monitor; 4-hour direct-sunlight match pilot on open cricket grounds. | Zero thermal shutdowns at 42°C ambient; zero stream dropouts over 4-hour match innings. |

&nbsp;