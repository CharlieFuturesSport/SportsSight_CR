drop table if exists #Events;
create table #Events (EventKey varchar(255) not null);

insert into #Events (EventKey) values
('12679_170626_Men_2ndTest_Eng_v_Nzl_Day_1'),
('12679_180626_Men_2ndTest_Eng_v_Nzl_Day_2'),
('12679_190626_Men_2ndTest_Eng_v_Nzl_Day_3'),
('12679_200626_Men_2ndTest_Eng_v_Nzl_Day_4'),
('12679_210626_Men_2ndTest_Eng_v_Nzl_Day_5');

-- 1) Assets returned
select
    replace(a.SportsEvent, '/', '') as EventKey,
    a.Asset,
    count_big(*) as AssetCount
from dbo.SportsSight_Raw_Assets a
inner join #Events e
    on replace(a.SportsEvent, '/', '') = e.EventKey
group by replace(a.SportsEvent, '/', ''), a.Asset
order by EventKey, AssetCount desc, a.Asset;

-- 2) Brands returned (raw)
select
    replace(b.SportsEvent, '/', '') as EventKey,
    b.Brand,
    count_big(*) as BrandCount
from dbo.SportsSight_Raw_Brands b
inner join #Events e
    on replace(b.SportsEvent, '/', '') = e.EventKey
group by replace(b.SportsEvent, '/', ''), b.Brand
order by EventKey, BrandCount desc, b.Brand;

-- 3) Brand-Asset returned (raw)
select
    replace(ba.SportsEvent, '/', '') as EventKey,
    ba.Brand,
    ba.Asset,
    count_big(*) as PairCount
from dbo.SportsSight_Raw_BrandAssets ba
inner join #Events e
    on replace(ba.SportsEvent, '/', '') = e.EventKey
group by replace(ba.SportsEvent, '/', ''), ba.Brand, ba.Asset
order by EventKey, PairCount desc, ba.Brand, ba.Asset;

-- 4) Optional normalized Brand-Asset view (strips 'Logo - Brand - ' and fixes Tyrrell-s)
select
    replace(ba.SportsEvent, '/', '') as EventKey,
    case
        when ba.Brand like 'Logo - Brand - %' then ltrim(substring(ba.Brand, len('Logo - Brand - ') + 1, 8000))
        else ba.Brand
    end as Brand_Normalized,
    ba.Asset,
    count_big(*) as PairCount
from dbo.SportsSight_Raw_BrandAssets ba
inner join #Events e
    on replace(ba.SportsEvent, '/', '') = e.EventKey
group by
    replace(ba.SportsEvent, '/', ''),
    case
        when ba.Brand like 'Logo - Brand - %' then ltrim(substring(ba.Brand, len('Logo - Brand - ') + 1, 8000))
        else ba.Brand
    end,
    ba.Asset
order by EventKey, PairCount desc, Brand_Normalized, ba.Asset;