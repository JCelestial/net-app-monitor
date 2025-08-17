using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace TestApp
{
    public class Startup
    {
        public void ConfigureServices(IServiceCollection services) { }

        public void Configure(IApplicationBuilder app, ILogger<Startup> logger)
        {
            app.UseRouting();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapGet("/", async context =>
                {
                    await context.Response.WriteAsync("Hello from TestApp!!");
                });

                // Simulate "500.37" for your log monitor (POC)
                endpoints.MapGet("/simulate50037", async context =>
                {
                    // Log text that mirrors IIS’s error page headline and detail
                    logger.LogError("HTTP Error 500.37 - ANCM Failed to Start Within Startup Time Limit. Default timeout is 120 seconds. (POC log)");
                    context.Response.StatusCode = 500;
                    await context.Response.WriteAsync("Simulated 500.37 logged.");
                });

                // Optional: simulate a slow request (not real 500.37, but handy for testing)
                endpoints.MapGet("/slow", async context =>
                {
                    await Task.Delay(5000);
                    await context.Response.WriteAsync("Done after 5s.");
                });
            });
        }
    }
}
