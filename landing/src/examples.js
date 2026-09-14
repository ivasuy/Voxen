export const examples = [
  {
    id: 'coding', label: 'Coding', destination: 'Cursor', selected: 'A request handler with retry logic',
    spoken: 'Check this authentication flow and make sure retries cannot create duplicate requests.',
    result: 'Review the selected authentication flow for duplicate requests caused by retries. Trace where a request can be sent more than once, including timeouts and concurrent calls.\n\nPreserve existing authentication behavior and public interfaces. Propose the smallest change that makes retry handling safe, and explain any tradeoffs before introducing new dependencies.\n\nAdd regression tests for repeated attempts, partial failures and overlapping requests. Run the affected test suite and report any remaining risks.',
  },
  {
    id: 'replies', label: 'Replies', destination: 'Slack', selected: 'Can we ship this today?',
    spoken: 'Tell him tomorrow morning is more realistic. I want to give it one more proper check.',
    result: 'Tomorrow morning is more realistic. I want to give it one more proper check before we ship, so we’re not rushing something out today. I’ll let you know if anything changes.',
  },
  {
    id: 'social', label: 'Social', destination: 'X', selected: null,
    spoken: 'Write a post about how benchmarks don’t tell us if coding models are useful on production tasks.',
    result: 'A great benchmark score doesn’t tell me whether a coding model can work in my codebase.\n\nCan it follow an unfamiliar pattern, handle a messy bug, and make a change without breaking something else?\n\nThat’s the evaluation I actually care about.',
  },
  {
    id: 'terminal', label: 'Terminal', destination: 'Terminal', selected: 'ECONNREFUSED 127.0.0.1:5432',
    spoken: 'Explain why this is happening and what I should check first.',
    result: 'Your app tried to connect to port 5432 on its own machine, but the connection was refused. Usually, no service is listening there.\n\nIf this is PostgreSQL, check that the database is running and listening on the expected port. Then check the host and port in your connection settings. If your app runs in a container, 127.0.0.1 refers to that container, not your Mac.',
  },
];
