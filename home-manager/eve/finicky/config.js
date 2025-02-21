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
      browser: ({ urlString }) => ({
        name: "Firefox",
      }),
    },
  ]
}
