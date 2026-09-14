'use client';

import { useEffect, useRef, useState } from 'react';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import {
  ArrowRight, ArrowUpRight, Check, ClipboardText, Code, Command, CaretDown,
  ChatCircle, Globe, Keyboard, LockKey, Microphone, TerminalWindow,
  TextAa, SlidersHorizontal, X, List, AppleLogo, DownloadSimple, GithubLogo,
} from '@phosphor-icons/react';
import { examples } from './examples';

gsap.registerPlugin(ScrollTrigger);
const icons = { coding: Code, replies: ChatCircle, social: Globe, terminal: TerminalWindow };
const downloadURL = 'https://github.com/ivasuy/Voxen/releases/latest/download/Voxen-macOS-arm64.zip';
const githubURL = 'https://github.com/ivasuy/Voxen';

function Logo() {
  return <a className="brand" href="#top" aria-label="Voxen home"><img src="/assets/voxen-logo.png" width="42" height="42" alt="" /><span>Voxen</span></a>;
}

function Navigation() {
  const [menu, setMenu] = useState(false);
  return <header className="navigation">
    <div className="shell nav-inner">
      <Logo />
      <nav id="main-navigation" className={menu ? 'nav-links is-open' : 'nav-links'} aria-label="Main navigation">
        <a href="#examples" onClick={() => setMenu(false)}>Context</a>
        <a href="#writing" onClick={() => setMenu(false)}>Writing</a>
        <a href="#history" onClick={() => setMenu(false)}>History</a>
        <a href="#setup" onClick={() => setMenu(false)}>Setup</a>
      </nav>
      <div className="nav-actions">
        <a className="button button-small" href={downloadURL} download="Voxen-macOS-arm64.zip">Download <DownloadSimple size={16} /></a>
        <button className="icon-button menu-toggle" aria-label={menu ? 'Close navigation' : 'Open navigation'} aria-expanded={menu} aria-controls="main-navigation" onClick={() => setMenu(!menu)} onKeyDown={e => { if (e.key === 'Escape') setMenu(false); }}>{menu ? <X size={22} /> : <List size={22} />}</button>
      </div>
    </div>
  </header>;
}

function ExampleLab() {
  const [active, setActive] = useState('coding');
  const [copy, setCopy] = useState('');
  const selected = examples.find(example => example.id === active);
  const activeRef = useRef(active);
  const timer = useRef();
  useEffect(() => { activeRef.current = active; setCopy(''); clearTimeout(timer.current); return () => clearTimeout(timer.current); }, [active]);
  async function copyExample() {
    const requested = active;
    try {
      await navigator.clipboard.writeText(selected.result);
      if (activeRef.current === requested) setCopy('Copied');
    } catch {
      if (activeRef.current === requested) setCopy('Select the example text and copy it manually.');
    }
    timer.current = setTimeout(() => setCopy(''), 4000);
  }
  function selectTab(event, index) {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % examples.length;
    if (event.key === 'ArrowLeft') next = (index + examples.length - 1) % examples.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = examples.length - 1;
    if (next !== undefined) { event.preventDefault(); setActive(examples[next].id); document.getElementById(`example-tab-${examples[next].id}`).focus(); }
  }
  return <div className="example-lab reveal">
    <div className="example-tabs" role="tablist" aria-label="Writing examples">
      {examples.map((example, index) => { const Icon = icons[example.id]; return <button key={example.id} id={`example-tab-${example.id}`} role="tab" aria-selected={active === example.id} aria-controls="example-panel" tabIndex={active === example.id ? 0 : -1} onClick={() => setActive(example.id)} onKeyDown={e => selectTab(e, index)}><Icon size={19} />{example.label}</button>; })}
    </div>
    <div id="example-panel" role="tabpanel" aria-labelledby={`example-tab-${active}`} tabIndex={0} className="example-body">
      <div className="example-input">
        <span className="destination"><span className="mono">Current app</span>{selected.destination}</span>
        {selected.selected && <div className="selection"><span className="label">Selected context</span><p>{selected.selected}</p></div>}
        <div className="voice-input"><Microphone size={22} /><div><span className="label">You say</span><blockquote>“{selected.spoken}”</blockquote></div></div>
      </div>
      <div className="example-output">
        <div className="output-heading"><span><img src="/assets/voxen-logo.png" width="27" height="27" alt="" />Ready for your clipboard</span><button className="icon-button" onClick={copyExample} aria-label="Copy example">{copy === 'Copied' ? <Check size={20} /> : <ClipboardText size={20} />}</button></div>
        <p className="generated-text">{selected.result}</p>
        <div className="example-note"><span>Illustrative example. Not live generation.</span><span role="status">{copy}</span></div>
      </div>
    </div>
  </div>;
}

function AppShot({ name, alt, className = '' }) {
  return <div className={`app-shot ${className}`}><img src={`/assets/${name}-dark.webp`} width="1560" height="1280" alt={alt} loading="lazy" /></div>;
}

function NativePreview() {
  const scene = useRef(null);
  const statuses = ['listening', 'writing', 'copied'];
  useEffect(() => {
    const context = gsap.context(() => {
      const frames = gsap.utils.toArray('.status-frame');
      gsap.set(frames, { opacity: 0, y: 0 });
      if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
        gsap.set(frames[0], { opacity: 1 });
        return;
      }
      const timeline = gsap.timeline({ repeat: -1 });
      frames.forEach((frame, index) => {
        timeline.fromTo(frame, { opacity: 0, y: 6 }, { opacity: 1, y: 0, duration: .3 }, index * 2.5)
          .to(frame, { opacity: 0, y: -6, duration: .25 }, index * 2.5 + 2.25);
      });
      const observer = new IntersectionObserver(([entry]) => entry.isIntersecting ? timeline.resume() : timeline.pause());
      observer.observe(scene.current);
      return () => observer.disconnect();
    }, scene);
    return () => context.revert();
  }, []);
  return <figure className="native-preview" ref={scene} aria-label="Animated preview of the actual Voxen app: Listening, Writing, then Copied. No microphone recording.">
    <div className="preview-window"><img className="native-window" src="/assets/hero-native-v2-2x.webp" srcSet="/assets/hero-native-v2-2x.webp 1560w, /assets/hero-native-v2-4x.webp 3120w" sizes="(max-width: 767px) calc(100vw - 84px), 48vw" width="1560" height="1280" fetchPriority="high" alt="Voxen's native command center with the Mode, Writing, History and Settings sidebar." /></div>
    <div className="native-status" aria-hidden="true">{statuses.map(status => <img key={status} className={`status-frame status-${status}`} src={`/assets/status-${status}-v2-6x.png`} width="960" height="324" alt="" />)}</div>
  </figure>;
}

function Writing() {
  const [tab, setTab] = useState('style');
  const tabs = [
    { id: 'style', icon: TextAa, title: 'Set your style', detail: 'Precise or elaborate. Paragraphs or bullets. Choose your tone, output language and word target.', image: 'writing' },
    { id: 'profile', icon: SlidersHorizontal, title: 'Give it your context', detail: 'Add what you do, who you write for and samples of your voice. Share this profile only when you enable it.', image: 'writing-profile' },
    { id: 'platforms', icon: Globe, title: 'Adapt to the destination', detail: 'Give different platforms their own preferences, including character limits, hashtags and how much detail to include.', image: 'writing-platforms' },
  ];
  const item = tabs.find(t => t.id === tab);
  return <section className="section shell writing" id="writing">
    <div className="section-intro reveal"><p className="eyebrow">Your voice, with direction</p><h2>More you.<br />Less default AI.</h2><p>You decide how much to say, what to assume, and how it should sound.</p></div>
    <div className="writing-stage">
      <div className="writing-options reveal" aria-label="Explore writing preferences">
        {tabs.map(({ id, icon: Icon, title, detail }) => <button key={id} aria-pressed={tab === id} aria-controls="writing-preview" onClick={() => setTab(id)}><Icon size={23} /><span><strong>{title}</strong><span>{detail}</span></span><ArrowUpRight size={19} /></button>)}
      </div>
      <figure className="writing-preview reveal" id="writing-preview">
        <AppShot name={item.image} alt={`Voxen Writing settings: ${item.title}. Native app preview with sample preferences.`} />
        <figcaption>Native macOS app. Sample preferences shown.</figcaption>
      </figure>
    </div>
  </section>;
}

function Workflow() {
  return <section className="workflow section" id="workflow">
    <div className="shell">
      <div className="section-intro reveal"><h2>A thought. A shortcut.<br />Back to what you’re doing.</h2><p>No new editor to open. No conversation to start over.</p></div>
      <div className="workflow-steps">
        <article className="workflow-step"><Keyboard size={28} /><h3>Bring the context.</h3><p>Stay in your app. Highlight a message, code or a paragraph if you want Voxen to work with it.</p><div className="step-detail"><Command size={18} /> Your current app + available selection</div></article>
        <article className="workflow-step"><Microphone size={28} /><h3>Say what you mean.</h3><p>Press your shortcut to speak, then press it again to finish. Voxen turns your request into the right kind of writing.</p><div className="step-detail"><kbd>⌥</kbd><kbd>space</kbd><span>Default shortcut</span></div></article>
        <article className="workflow-step"><ClipboardText size={28} /><h3>Review. Paste. Done.</h3><p>The generated result is copied to your clipboard. You choose where to paste it, and when to send it.</p><div className="step-detail"><kbd>⌘</kbd><kbd>V</kbd><span>Always in your control</span></div></article>
      </div>
    </div>
  </section>;
}

function Privacy() {
  return <section className="section shell privacy" id="history">
    <div className="section-intro reveal"><h2>Good words.<br />Worth keeping.</h2><p>Find the response you need, with its app or site attached. Keep your context under your control.</p></div>
    <div className="privacy-grid">
      <article className="privacy-copy reveal"><LockKey size={30} /><h3>Only when you ask.</h3><p>Recording and context capture begin with your shortcut. No continuous screen capture, background listening or automatic sending.</p><div className="privacy-detail"><h4>Know what leaves your Mac.</h4><p>Audio goes to AssemblyAI. Your transcript, captured context and enabled writing preferences go to your chosen model through OpenRouter. Optional research sends a public search query.</p></div><a className="text-link" href="#questions">Read the details <ArrowRight size={18} /></a></article>
      <article className="history-feature reveal"><div><h3>Your useful words, kept nearby.</h3><p>Find a past response by its app or site. History stays local, and you can turn it off or delete it.</p></div><AppShot name="history" alt="Voxen local response history with synthetic Slack, Cursor and social examples." /></article>
    </div>
  </section>;
}

function Setup() {
  return <section className="section setup shell" id="setup">
    <div className="setup-heading reveal"><img src="/assets/voxen-logo.png" width="74" height="74" alt="" /><h2>Make room for<br />your next thought.</h2><p>Native for macOS 14+ on Apple Silicon.<br />Bring your own AssemblyAI and OpenRouter keys.</p><div className="setup-actions"><a className="button" href={downloadURL} download="Voxen-macOS-arm64.zip">Download for macOS <DownloadSimple size={18} /></a><a className="button button-secondary" href={githubURL} target="_blank" rel="noreferrer">View on GitHub <GithubLogo size={18} /></a></div><p className="availability">Free and open source. GitHub builds are ad-hoc signed, not Apple-notarized.</p></div>
    <div className="setup-checklist reveal">
      <h3>A small setup. Then one shortcut.</h3>
      <ol>
        <li><AppleLogo size={23} /><div><strong>Download the Mac app</strong><p>Get the latest release from GitHub, unzip it, and move Voxen to Applications.</p></div></li>
        <li><SlidersHorizontal size={23} /><div><strong>Add your API keys</strong><p>Choose a writing model in Settings. API usage and optional search are billed by your providers.</p><div className="provider-links"><a href="https://www.assemblyai.com/dashboard/signup" target="_blank" rel="noreferrer">AssemblyAI <ArrowUpRight size={14} /></a><a href="https://openrouter.ai/settings/keys" target="_blank" rel="noreferrer">OpenRouter <ArrowUpRight size={14} /></a></div></div></li>
        <li><Microphone size={23} /><div><strong>Enable permissions</strong><p>Allow the microphone. Enable Accessibility for website and selected-text context.</p></div></li>
      </ol>
    </div>
  </section>;
}

const questions = [
  ['Is this just voice dictation?', 'Dictation cleans up what you said. Voxen also uses your request, current app, available website context and highlighted text to decide what to write. Ask for a reply, an explanation or an engineering prompt, rather than dictating every word.'],
  ['Will it paste or send anything automatically?', 'No. Only the generated response is copied to your clipboard. You review it, paste with Command + V and decide whether to send it. The landing-page examples are static demonstrations and do not record audio or call an AI model.'],
  ['Does it work with every website?', 'Website and highlighted-text capture depend on what the browser exposes through macOS Accessibility. They are best effort, not guaranteed. If context is unavailable, use a manual mode and include the missing context in your spoken request. No browser extension is required.'],
  ['What is stored, and what is shared?', 'API keys are stored in macOS Keychain. Writing preferences and your optional profile are stored locally. When enabled, local history keeps up to 100 generated responses; it can be disabled or deleted. Voxen does not keep separate audio, transcript or selected-source archives. Audio is sent to AssemblyAI; writing requests go through OpenRouter to your selected model. Provider retention policies still apply.'],
  ['Can it research a current topic?', 'Voxen can request optional web research when a task needs current public facts. Ordinary replies, rewrites and personal project ideas do not need a search. Research can cost extra and may return no useful sources. Always check factual claims before posting.'],
  ['Do I need a subscription?', 'Voxen uses your own AssemblyAI and OpenRouter API keys. Provider usage may cost money, including optional web search. There is no Voxen account or subscription flow. The setup guide lists current model options and limitations.'],
];

export default function App() {
  const root = useRef(null);
  useEffect(() => {
    // Entry establishes hierarchy; scroll reveals follow the workflow reading order.
    // MatchMedia also reacts when reduced-motion is changed while the page is open.
    const context = gsap.context(() => {
      const media = gsap.matchMedia();
      media.add('(prefers-reduced-motion: no-preference)', () => {
        gsap.from('.hero-copy > *', { y: 18, opacity: 0, stagger: 0.09, duration: 0.7, ease: 'power2.out' });
        gsap.from('.native-preview', { y: 24, duration: 0.7, ease: 'power2.out' });
        gsap.utils.toArray('.reveal').forEach(element => {
          gsap.from(element, { y: 24, opacity: 0, duration: 0.65, ease: 'power2.out', scrollTrigger: { trigger: element, start: 'top 92%', once: true } });
        });
        gsap.from('.workflow-step', { y: 32, opacity: 0, stagger: 0.18, duration: 0.7, scrollTrigger: { trigger: '.workflow-steps', start: 'top 85%', once: true } });
        gsap.to('.hero-atmosphere', { yPercent: 12, scale: 1.05, ease: 'none', scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: .8 } });
        // Adapted from Orbit Matter's scroll-driven introduction: reveal the idea in reading order.
        gsap.from('.context-word', { y: 20, opacity: .68, stagger: .12, ease: 'none', scrollTrigger: { trigger: '.context-story', start: 'top 78%', end: 'center 48%', scrub: 1 } });
        gsap.from('.context-outcomes > span', { y: 14, opacity: 0, stagger: .1, duration: .55, scrollTrigger: { trigger: '.context-outcomes', start: 'top 88%', once: true } });
        gsap.from('.footer-wordmark', { yPercent: 25, opacity: .68, ease: 'none', scrollTrigger: { trigger: '.site-footer', start: 'top 85%', end: 'bottom bottom', scrub: 1 } });
      });
    }, root);
    return () => context.revert();
  }, []);
  return <div ref={root} id="top">
    <a className="skip-link" href="#main">Skip to content</a>
    <Navigation />
    <main id="main">
      <section className="hero">
        <div className="hero-atmosphere" aria-hidden="true"><span /><span /><span /><span /></div>
        <div className="shell hero-inner">
          <div className="hero-copy"><img className="hero-mark" src="/assets/voxen-logo.png" width="58" height="58" alt="" /><p className="eyebrow">A voice intent layer for macOS</p><h1>Speak intent, <span>not text.</span></h1><p className="hero-description">Turn a rough thought into writing shaped by your app, selected context and voice.</p><div className="hero-actions"><a className="button" href={downloadURL} download="Voxen-macOS-arm64.zip">Download for macOS <DownloadSimple size={19} /></a><a className="button button-secondary" href={githubURL} target="_blank" rel="noreferrer">View on GitHub <GithubLogo size={19} /></a></div></div>
          <NativePreview />
        </div>
      </section>
      <section className="context-story shell" aria-label="The idea behind Voxen">
        <p className="context-kicker">Same voice. Different destination.</p>
        <h2>{'Context decides what belongs on your clipboard.'.split(' ').map((word, index) => <span className="context-word" key={index}>{word} </span>)}</h2>
        <div className="context-outcomes" aria-label="Example uses"><span><Code size={19} /> Engineering prompts</span><span><ChatCircle size={19} /> Thoughtful replies</span><span><Globe size={19} /> Social posts</span><span><TerminalWindow size={19} /> Technical explanations</span></div>
      </section>
      <section className="section shell examples" id="examples"><div className="section-intro reveal"><h2>Different context.<br />The right words.</h2><p>A request is more than a transcript. See how the destination changes what belongs on your clipboard.</p></div><ExampleLab /></section>
      <Workflow />
      <Writing />
      <Privacy />
      <Setup />
      <section className="section shell questions" id="questions"><h2 className="reveal">A few things to know.</h2><div className="faq-list reveal">{questions.map(([question, answer]) => <details key={question}><summary>{question}<CaretDown size={20} /></summary><p>{answer}</p></details>)}</div></section>
    </main>
    <footer className="site-footer">
      <div className="shell footer-top"><div className="footer-brand"><Logo /><p>A voice intent layer for macOS.<br />Speak intent. Keep your voice.</p></div><nav aria-label="Footer product links"><h3>Explore</h3><a href="#examples">Context</a><a href="#writing">Writing</a><a href="#history">History</a><a href="#setup">Setup</a></nav><nav aria-label="Footer resources"><h3>Resources</h3><a href={githubURL} target="_blank" rel="noreferrer">GitHub <GithubLogo size={13} /></a><a href="/setup.md" download="Voxen-setup.md">Build instructions</a><a href="#questions">Questions</a><a href="https://www.assemblyai.com/dashboard/signup" target="_blank" rel="noreferrer">AssemblyAI key <ArrowUpRight size={13} /></a><a href="https://openrouter.ai/settings/keys" target="_blank" rel="noreferrer">OpenRouter key <ArrowUpRight size={13} /></a></nav><a className="button" href={downloadURL} download="Voxen-macOS-arm64.zip">Download for macOS <DownloadSimple size={18} /></a></div>
      <div className="shell footer-wordmark" aria-hidden="true">Voxen</div>
      <div className="shell footer-bottom"><p>Local-first macOS utility.</p><p>macOS 14+ · Apple Silicon</p><a href="#top">Back to top <ArrowUpRight size={15} /></a></div>
    </footer>
  </div>;
}
