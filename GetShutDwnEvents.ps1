Get-EventLog -LogName system -Source user32 | Select TimeGenerated, Message | sort message | ft -Wrap
