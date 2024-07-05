local Config = lib.require('config')

RSGCore.Commands.Add('myjobs', 'Opens your job menu', {}, false, function(source)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    TriggerClientEvent('rsg-multijob:client:openmenu', src)
end)

local function GetJobCount(cid)
    local result = MySQL.query.await('SELECT COUNT(*) as jobCount FROM player_jobs WHERE citizenid = ?', {cid})
    local jobCount = result[1].jobCount
    return jobCount
end

local function CanSetJob(cid, jobName)
    local jobs = MySQL.query.await('SELECT job, grade FROM player_jobs WHERE citizenid = ? ', {cid})
    if not jobs then return false end
    for i = 1, #jobs do
        if jobs[i].job == jobName then
            return true, jobs[i].grade
        end
    end
    return false
end

lib.callback.register('rsg-multijob:server:myJobs', function(source)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local storeJobs = {}
    local result = MySQL.query.await('SELECT * FROM player_jobs WHERE citizenid = ?', {Player.PlayerData.citizenid})
    for k, v in pairs(result) do
        local job = RSGCore.Shared.Jobs[v.job]

        if not job then 
            return error(('MISSING JOB FROM jobs.lua: "%s" | CITIZEN ID: %s'): format(v.job, Player.PlayerData.citizenid)) 
        end
        
        local grade = job.grades[tostring(v.grade)]

        if not grade then 
            return error(('MISSING JOB GRADE for "%s". GRADE MISSING: %s | CITIZEN ID: %s'): format(v.job, v.grade, Player.PlayerData.citizenid)) 
        end

        storeJobs[#storeJobs + 1] = {
            job = v.job,
            salary = grade.payment,
            jobLabel = job.label,
            gradeLabel = grade.name,
            grade = v.grade,
        }
    end
    return storeJobs
end)

RegisterNetEvent('rsg-multijob:server:changeJob', function(job)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if Player.PlayerData.job.name == job then 
        RSGCore.Functions.Notify(src, 'Your current job is already set to this.', 'error') 
        return 
    end

    local jobInfo = RSGCore.Shared.Jobs[job]
    if not jobInfo then 
        RSGCore.Functions.Notify(src, 'Invalid job.', 'error') 
        return 
    end

    local cid = Player.PlayerData.citizenid
    local canSet, grade = CanSetJob(cid, job)
    
    if not canSet then 
        return 
    end

    Player.Functions.SetJob(job, grade)
    Player.Functions.SetJobDuty(false)
    TriggerClientEvent('RSGCore:Client:SetDuty', src, false)
    RSGCore.Functions.Notify(src, 'Your job is now: ' .. jobInfo.label)
end)

RegisterNetEvent('rsg-multijob:server:newJob', function(newJob)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local hasJob = false
    local cid = Player.PlayerData.citizenid
    if newJob.name == 'unemployed' then return end
    local result = MySQL.query.await('SELECT * FROM player_jobs WHERE citizenid = ? AND job = ?', {cid, newJob.name}) 
    if result[1] then
        MySQL.query.await('UPDATE player_jobs SET grade = ? WHERE job = ? and citizenid = ?', {newJob.grade.level, newJob.name, cid})
        hasJob = true
        return
    end
    if not hasJob and GetJobCount(cid) < Config.MaxJobs then 
        MySQL.insert.await('INSERT INTO player_jobs (citizenid, job, grade) VALUE (?, ?, ?)', {cid, newJob.name, newJob.grade.level})
    else
        return RSGCore.Functions.Notify(src, 'You have the max amount of jobs.', 'error')
    end
end)

RegisterNetEvent('rsg-multijob:server:deleteJob', function(job)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    MySQL.query.await('DELETE FROM player_jobs WHERE citizenid = ? and job = ?', {Player.PlayerData.citizenid, job})
    RSGCore.Functions.Notify(src, 'You deleted '..RSGCore.Shared.Jobs[job].label..' job from your menu.')
    if Player.PlayerData.job.name == job then
        Player.Functions.SetJob('unemployed', 0)
    end
end)

RegisterNetEvent('rsg-bossmenu:server:FireEmployee', function(target) -- Removes job when fired from rsg-bossmenu.
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local Employee = RSGCore.Functions.GetPlayerByCitizenId(target)
    if Employee then
        local oldJob = Employee.PlayerData.job.name
        MySQL.query.await('DELETE FROM player_jobs WHERE citizenid = ? AND job = ?', {Employee.PlayerData.citizenid, oldJob})
    else
        local player = MySQL.query.await('SELECT * FROM players WHERE citizenid = ? LIMIT 1', { target })
        if player[1] then
            Employee = player[1]
            Employee.job = json.decode(Employee.job)
            if Employee.job.grade.level > Player.PlayerData.job.grade.level then return end
            MySQL.query.await('DELETE FROM player_jobs WHERE citizenid = ? AND job = ?', {target, Employee.job.name})
        end
    end
end)

local function adminRemoveJob(src, id, job)
    local Player = RSGCore.Functions.GetPlayer(id)
    local cid = Player.PlayerData.citizenid
    local result = MySQL.query.await('SELECT * FROM player_jobs WHERE citizenid = ? AND job = ?', {cid, job})
    if result[1] then
        MySQL.query.await('DELETE FROM player_jobs WHERE citizenid = ? AND job = ?', {cid, job})
        RSGCore.Functions.Notify(src, ('Job: %s was removed from ID: %s'):format(job, id), 'success')
        if Player.PlayerData.job.name == job then
            Player.Functions.SetJob('unemployed', 0)
        end
    else
        RSGCore.Functions.Notify(src, 'Player doesn\'t have this job?', 'error')
    end
end

RSGCore.Commands.Add('removejob', "Remove a job from the player's multijob.", { { name = 'id', help = 'ID of the player' }, { name = 'job', help = 'Name of Job' } }, true, function(source, args)
    local src = source
    if not args[1] then 
        RSGCore.Functions.Notify(src, 'Must provide a player id.', 'error') 
        return 
    end
    if not args[2] then 
        RSGCore.Functions.Notify(src, 'Must provide the name of the job to remove from the player.', 'error') 
        return 
    end
    local id = tonumber(args[1])
    local Player = RSGCore.Functions.GetPlayer(id)
    if not Player then RSGCore.Functions.Notify(src, 'Player not online.', 'error') return end

    adminRemoveJob(src, id, args[2])
end, 'admin')