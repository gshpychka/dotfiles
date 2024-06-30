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
          "Teams",
          "Leapp"
        ].some(
          appName => opener.path.toLowerCase().includes(
            appName.toLowerCase()
          )
        );
        const basedOnUrl = [
          "aws.amazon.com",
          "gitlab.com",
          "atlassian",
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
