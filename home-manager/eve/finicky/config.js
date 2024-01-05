module.exports = {
  defaultBrowser: ({ urlString }) => ({
    name: "Google Chrome",
  }), 
  options: {
    checkForUpdate: false
  },
  handlers: [
    {
      match: ({ opener, url }) => {
        const basedOnOpener =  [
          "Slack",
          "Leapp"
        ].some(
          appName => opener.path.toLowerCase().includes(
            appName.toLowerCase()
          )
        );
        const basedOnUrl = [
          "aws.amazon.com",
          "github.com",
        ].some(
          targetHostName => url.host.toLowerCase().includes(
            targetHostName.toLowerCase()
          )
        );
        return basedOnOpener || basedOnUrl;
      },
      browser: ({ urlString }) => ({
        name: "Firefox",
      }),
    },
  ]
}
