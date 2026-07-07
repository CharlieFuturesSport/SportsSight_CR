drop table if exists #Events;
create table #Events (EventKey varchar(255) not null);

insert into #Events (EventKey) values
('12679_170626_Men_2ndTest_Eng_v_Nzl_Day_1'),
('12679_180626_Men_2ndTest_Eng_v_Nzl_Day_2'),
('12679_190626_Men_2ndTest_Eng_v_Nzl_Day_3'),
('12679_200626_Men_2ndTest_Eng_v_Nzl_Day_4'),
('12679_210626_Men_2ndTest_Eng_v_Nzl_Day_5');

select
    c.Brand,
    c.Creative,
    count_big(*) as OCRCount
from dbo.Toolkit_Cleaned_OCR_Results c
inner join #Events e
    on replace(c.SportsEvent, '/', '') = e.EventKey
where c.AccessFlag = 'ecb_2026'
group by c.Brand, c.Creative
order by OCRCount desc, c.Brand, c.Creative;