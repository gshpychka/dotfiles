export default {
  defaultBrowser: () => ({
    name: "Google Chrome",
  }), 
  options: {
    checkForUpdate: false
  },
  handlers: [
    {
      match: (url, { opener }) => {
        const basedOnOpener =  [
          "Teams",
          "Leapp",
          "Ghostty",
          "Claude",
          "Codex",
          "ChatGPT",
          "Slack",
          "Notion",
          "Linear",
          "Zoom"
        ].some(
          appName => {
            try {
              return opener.path.toLowerCase().includes(
                appName.toLowerCase()
              )
            } catch {
              return false;
            }
          }
        );
        const basedOnUrl = [
          "aws.amazon.com",
          "gitlab.com",
          "atlassian",
          "awsapps.com",
          "learn.microsoft.com",
          "linear.app",
          "mcp.notion.com"
        ].some(
          targetHostName => {
            try {
              return url.host.toLowerCase().includes(
                targetHostName.toLowerCase()
              )
            } catch {
              return false;
            }
          }
        );
        return basedOnOpener || basedOnUrl;
      },
      browser: () => ({
        name: "Firefox",
      }),
    },
  ]
}
