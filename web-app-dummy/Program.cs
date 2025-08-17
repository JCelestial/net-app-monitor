using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.EventLog;
using System;
using System.Threading;

namespace TestApp
{
    public class Program
    {
        public static void Main(string[] args)
        {
            Thread.Sleep(TimeSpan.FromSeconds(15)); // TEMP: force slow startup
            CreateHostBuilder(args).Build().Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
            .ConfigureLogging(l =>
            {
                l.ClearProviders();
                l.AddConsole();
                l.AddEventLog(new EventLogSettings { SourceName = "TestApp", LogName = "Application" });
            })
            .ConfigureWebHostDefaults(w => w.UseStartup<Startup>());
        
    }
}
